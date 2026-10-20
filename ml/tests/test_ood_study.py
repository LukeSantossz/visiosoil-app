"""The descriptor-distance guard (SPEC 0176): centroids and a pooled diagonal
variance fitted on a training side, held-out soil scored by folds that never
saw it, the excluded Siltosa scored and never trained on, and the rule.

The study is driven with fake featurisers over synthetic entries, as
`test_field_study.py` drives the field study, so nothing decodes an image.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

from src import ood, ood_study
from src.arms.probe import STANDARDISE_STEP, fit_probe
from src.config import load_config
from src.dataset import create_folds, fold_split
from src.descriptors import feature_names

from .support import real_manifest_or_skip

WIDTH = len(feature_names())
EXCLUDED = "Siltosa"
#: A column no soil row reaches, so a test can tell an excluded row anywhere.
MARKER = 99.0


def _seed_of(path: str) -> int:
    return int.from_bytes(
        hashlib.blake2b(path.encode("utf-8"), digest_size=8).digest(), "big"
    )


def _fake(separation=2.0):
    """Patches around a class centre read from the file's name; an excluded
    photograph's rows carry the marker in the last column."""

    def featurise(entry, cfg):
        name = Path(entry["path"]).stem.split("-")[0].replace("_", " ")
        generator = np.random.default_rng(_seed_of(entry["path"]) % (2**32))
        rows = generator.normal(0.0, 1.0, size=(3, WIDTH))
        if name in cfg["classes"]:
            rows[:, cfg["classes"].index(name)] += separation
        else:
            rows[:, -1] = MARKER
        return rows

    return featurise


@pytest.fixture
def cfg():
    return load_config()


def _archive_manifest(tmp_path, cfg, groups_per_class=4, train_only=()):
    """A real fold manifest of synthetic groups, two photographs each."""
    root = tmp_path / "datasets" / "v-fixture"
    images: dict[str, list[str]] = {}
    sample_ids: dict[str, str] = {}
    for name in cfg["classes"]:
        slug = name.replace(" ", "_")
        images[name] = []
        for index in range(groups_per_class):
            sample = f"{slug}-g{index}"
            for setting in ("dish", "paper"):
                path = str(root / f"images/{sample}_{setting}.jpg")
                images[name].append(path)
                sample_ids[path] = sample
    return create_folds(
        images,
        k=2,
        repeats=1,
        seed=42,
        splits_dir=str(tmp_path / "splits"),
        dataset_root=str(root),
        sample_ids=sample_ids,
        dataset_version="v-fixture",
        manifest_digest="0" * 64,
        train_only_samples=set(train_only),
    )


def _excluded(tmp_path, samples=3, photographs=2):
    root = tmp_path / "datasets" / "v-fixture"
    return [
        {
            "path": str(root / f"images/{EXCLUDED}-s{sample}_{photo}.jpg"),
            "class": EXCLUDED,
            "group": f"{EXCLUDED}::{EXCLUDED}-s{sample}",
        }
        for sample in range(samples)
        for photo in range(photographs)
    ]


def _field(cfg):
    return [
        {
            "path": f"/field/{name.replace(' ', '_')}-F{index}.png",
            "class": name,
            "label": cfg["classes"].index(name),
            "sample": f"{name}/F{index}",
        }
        for name in cfg["classes"]
        for index in range(2)
    ]


def test_the_centroids_and_variance_come_from_the_training_side():
    rows = np.array([[0.0, 1.0], [2.0, 3.0], [4.0, 0.0], [6.0, 2.0], [8.0, 4.0]])
    labels = np.array([0, 0, 1, 1, 1])

    guard = ood.fit_guard(rows, labels, classes=2)

    z = (rows - rows.mean(axis=0)) / rows.std(axis=0)
    centroids = np.stack([z[labels == 0].mean(axis=0), z[labels == 1].mean(axis=0)])
    residual = z - centroids[labels]
    np.testing.assert_allclose(guard.centroids, centroids)
    np.testing.assert_allclose(guard.variance, (residual**2).sum(axis=0) / (5 - 2))


def test_the_standardisation_is_the_probes(cfg):
    generator = np.random.default_rng(3)
    rows = generator.normal(size=(40, WIDTH))
    labels = np.arange(40) % 4

    guard = ood.fit_guard(rows, labels, classes=4)
    scaler = fit_probe(rows, labels, c=1.0).named_steps[STANDARDISE_STEP]

    np.testing.assert_allclose(guard.mean, scaler.mean_)
    np.testing.assert_allclose(guard.scale, scaler.scale_)


def test_a_patch_scores_against_its_nearest_class():
    guard = ood.Guard(
        mean=np.zeros(3),
        scale=np.ones(3),
        centroids=np.array([[0.0, 0.0, 0.0], [10.0, 10.0, 10.0]]),
        variance=np.array([1.0, 4.0, 9.0]),
    )
    rows = np.array([[0.0, 0.0, 0.0], [10.0, 10.0, 10.0], [11.0, 12.0, 13.0], [-1.0, 2.0, -3.0]])

    np.testing.assert_allclose(ood.patch_distances(guard, rows), [0.0, 0.0, 1.0, 1.0])


def test_a_photograph_scores_the_mean_of_its_patches():
    guard = ood.Guard(
        mean=np.zeros(2),
        scale=np.ones(2),
        centroids=np.array([[0.0, 0.0]]),
        variance=np.array([1.0, 1.0]),
    )
    block = np.array([[0.0, 0.0], [2.0, 2.0], [1.0, 1.0]])

    assert ood.photograph_score(guard, block) == pytest.approx(1.0)


def test_a_feature_without_spread_is_refused():
    rows = np.array([[0.0, 1.0], [0.0, 2.0], [0.0, 3.0], [0.0, 4.0]])
    labels = np.array([0, 0, 1, 1])
    with pytest.raises(ValueError, match="no within-class spread"):
        ood.fit_guard(rows + [[1.0, 0.0], [1.0, 0.0], [5.0, 0.0], [5.0, 0.0]], labels, classes=2)


def test_held_out_soil_is_scored_by_a_fit_that_never_saw_it(tmp_path, cfg):
    manifest = _archive_manifest(tmp_path, cfg, train_only=("Media-g3",))
    report = ood_study.run_study(cfg, manifest, _excluded(tmp_path), featuriser=_fake())

    soil = report["held_out_soil"]["photographs"]
    every = [e for side in fold_split(manifest, 0, 0).values() for e in side]
    splittable = {e["path"] for e in every if e["group"] != "Media::Media-g3"}
    assert sorted(r["path"] for r in soil) == sorted(splittable)
    for record in soil:
        train = fold_split(manifest, 0, record["fold"])["train"]
        assert record["group"] not in {e["group"] for e in train}


def test_siltosa_never_trains(tmp_path, cfg, monkeypatch):
    fitted = []
    real_fit = ood_study.fit_guard

    def spy(features, labels, *, classes):
        fitted.append(features)
        return real_fit(features, labels, classes=classes)

    monkeypatch.setattr(ood_study, "fit_guard", spy)
    report = ood_study.run_study(
        cfg, _archive_manifest(tmp_path, cfg), _excluded(tmp_path), featuriser=_fake()
    )

    assert fitted and all(not np.any(f[:, -1] == MARKER) for f in fitted)
    excluded = report["excluded"]["photographs"]
    assert len(excluded) == 6
    for record in excluded:
        assert len(record["fold_scores"]) == 2
        assert record["score"] == pytest.approx(np.mean(record["fold_scores"]))


def test_the_threshold_is_the_held_out_quantile(tmp_path, cfg):
    report = ood_study.run_study(
        cfg, _archive_manifest(tmp_path, cfg), _excluded(tmp_path), featuriser=_fake()
    )

    scores = [r["score"] for r in report["held_out_soil"]["photographs"]]
    assert report["threshold"] == pytest.approx(np.quantile(scores, 0.99))
    refused = sum(s > report["threshold"] for s in scores)
    assert report["held_out_soil"]["refused"] == refused


@pytest.mark.parametrize(
    "refused, auroc, field, verdict",
    [
        (4, 0.80, None, "open"),
        (4, 0.80, 0.10, "pass"),
        (4, 0.80, 0.11, "fail"),
        (3, 0.95, None, "fail"),
        (6, 0.79, None, "fail"),
    ],
)
def test_the_rule_is_applied_as_written(refused, auroc, field, verdict):
    rule = ood_study.apply_rule(refused=refused, auroc=auroc, field_refusal=field)

    assert rule["verdict"] == verdict
    assert rule["siltosa_refused"] == (refused >= 4)
    assert rule["auroc"] == (auroc >= 0.80)
    assert rule["field"] == ("open" if field is None else field <= 0.10)


def test_the_version_is_the_configurations(cfg, monkeypatch):
    read = []
    monkeypatch.setattr(ood_study, "resolve_paths", lambda c: cfg)
    monkeypatch.setattr(
        ood_study, "load_folds_for_config", lambda c, d: read.append(d) or {}
    )
    monkeypatch.setattr("sys.argv", ["ood_study", "--version", "v2"])

    with pytest.raises(ValueError, match="dataset version"):
        ood_study.main()
    assert read == []


def test_the_excluded_rows_are_the_archives_siltosa(cfg):
    manifest = real_manifest_or_skip()
    entries = ood_study.excluded_entries(manifest, cfg)

    assert {e["class"] for e in entries} == {EXCLUDED}
    assert len(entries) == 6 and len({e["group"] for e in entries}) == 3


def test_the_study_runs_end_to_end(tmp_path, cfg, monkeypatch, capsys):
    models = tmp_path / "models"
    manifest = _archive_manifest(tmp_path, cfg)
    monkeypatch.setattr(
        ood_study,
        "resolve_paths",
        lambda c: {**c, "export": {**c["export"], "output_dir": str(models)}},
    )
    monkeypatch.setattr(ood_study, "load_folds_for_config", lambda c, d: manifest)
    monkeypatch.setattr(ood_study, "read_manifest", lambda root, classes: None)
    monkeypatch.setattr(ood_study, "excluded_entries", lambda m, c: _excluded(tmp_path))
    monkeypatch.setattr(ood_study, "load_field_export", lambda d, c: _field(c))
    monkeypatch.setattr(ood_study, "descriptor_features", _fake())
    monkeypatch.setattr(ood_study, "field_features", _fake(separation=0.0))
    monkeypatch.setattr("sys.argv", ["ood_study", "--version", "v1", "--field", "x"])

    ood_study.main()

    report = json.loads((models / "v1" / "ood_study" / "report.json").read_text())
    assert report["threshold"] > 0
    assert set(report["held_out_soil"]["per_class"]) == set(cfg["classes"])
    assert report["excluded"]["refused"] <= len(report["excluded"]["photographs"]) == 6
    assert 0.0 <= report["auroc"] <= 1.0
    assert set(report["field"]["per_class"]) == set(cfg["classes"])
    assert report["rule"]["field"] in (True, False)
    assert "verdict:" in capsys.readouterr().out
