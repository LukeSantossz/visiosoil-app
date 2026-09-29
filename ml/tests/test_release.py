"""The release fit (SPEC 0082).

`src.release.release_fit` selects `C` over every fold of the manifest, refits
on every photograph and writes the contract. These tests drive it with a fake
featuriser over a synthetic manifest, so nothing decodes an image. The last one
reads the committed release itself, which no test regenerates: its numbers pass
through the descriptors' FFT and `log`, and those drift in the last digits
across CPUs (SPEC 0080).
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

from src import release
from src.arms.probe import C_GRID, fit_probe
from src.config import load_config
from src.contract import descriptor_contract
from src.dataset import create_folds
from src.descriptors import feature_names
from tests.test_contract import ABSOLUTE, RELATIVE, evaluate

REPO_ROOT = Path(__file__).resolve().parents[2]
COMMITTED_RELEASE = REPO_ROOT / "assets" / "models" / "spec.json"

K = 2
REPEATS = 2
SEED = 42
GROUPS_PER_CLASS = 6
PATCHES = 3
WIDTH = len(feature_names())


def _seed_of(path: str) -> int:
    return int.from_bytes(hashlib.blake2b(path.encode("utf-8"), digest_size=8).digest(), "big")


def _class_of(path: str, classes) -> int:
    """Read from the path, never from the label a featuriser must not see."""
    slug = Path(path).stem.split("-")[0]
    return [name.replace(" ", "_") for name in classes].index(slug)


def featuriser_at(separation: float):
    """Patches around a class-dependent centre, a function of the path alone."""

    def featurise(entry, cfg):
        generator = np.random.default_rng(_seed_of(entry["path"]) % (2**32))
        centre = np.zeros(WIDTH)
        centre[_class_of(entry["path"], cfg["classes"])] = separation
        return centre + generator.normal(0.0, 1.0, size=(PATCHES, WIDTH))

    return featurise


@pytest.fixture
def cfg():
    return load_config()


@pytest.fixture
def folds(tmp_path, cfg):
    """Groups of the configured classes, the first of each class train-only."""
    root = tmp_path / "datasets" / "v-fixture"
    images: dict[str, list[str]] = {}
    sample_ids: dict[str, str] = {}
    train_only = []
    for name in cfg["classes"]:
        slug = name.replace(" ", "_")
        images[name] = []
        for index in range(GROUPS_PER_CLASS):
            sample = f"{slug}-{index}"
            if index == 0:
                train_only.append(sample)
            for setting in ("dish", "paper"):
                path = str(root / f"images/{sample}_{setting}.jpg")
                images[name].append(path)
                sample_ids[path] = sample
    return create_folds(
        images,
        k=K,
        repeats=REPEATS,
        seed=SEED,
        splits_dir=str(tmp_path / "splits"),
        dataset_root=str(root),
        sample_ids=sample_ids,
        dataset_version="v-fixture",
        manifest_digest="0" * 64,
        train_only_samples=train_only,
    )


def _every_path(folds) -> list[str]:
    return [path for group in folds["groups"].values() for path in group["images"]]


def _train_only_groups(folds) -> set[str]:
    return {group_id for group_id, group in folds["groups"].items() if group["train_only"]}


def _spy(monkeypatch, name):
    """Record every call to `release.<name>` and let it run."""
    calls = []
    real = getattr(release, name)

    def spy(*args, **kwargs):
        result = real(*args, **kwargs)
        calls.append((args, kwargs, result))
        return result

    monkeypatch.setattr(release, name, spy)
    return calls


def test_release_selects_c_over_every_manifest_fold(monkeypatch, cfg, folds):
    scored = _spy(monkeypatch, "_photograph_accuracy")
    fitted = release.release_fit(
        cfg, folds, model_version="test", featuriser=featuriser_at(1.0)
    )

    assert len(scored) == REPEATS * K * len(C_GRID)
    accuracies = np.array([result for _, _, result in scored]).reshape(
        REPEATS * K, len(C_GRID)
    )
    means = accuracies.mean(axis=0)
    selection = fitted.selection
    assert selection["scored_folds"] == REPEATS * K
    assert selection["c_grid"] == [float(c) for c in C_GRID]
    assert [row["mean_accuracy"] for row in selection["mean_accuracy_per_c"]] == [
        pytest.approx(value) for value in means
    ]
    best = means.max()
    assert selection["chosen_c"] == min(c for c, m in zip(C_GRID, means) if m == best)


def test_a_tie_goes_to_the_strongest_regularisation(cfg, folds):
    fitted = release.release_fit(
        cfg, folds, model_version="test", featuriser=featuriser_at(50.0)
    )
    assert {row["mean_accuracy"] for row in fitted.selection["mean_accuracy_per_c"]} == {1.0}
    assert fitted.selection["chosen_c"] == min(C_GRID)


def test_train_only_groups_are_never_scored(monkeypatch, cfg, folds):
    scored = _spy(monkeypatch, "_photograph_accuracy")
    release.release_fit(cfg, folds, model_version="test", featuriser=featuriser_at(1.0))

    restricted = _train_only_groups(folds)
    assert restricted, "the fixture holds no train-only group"
    scored_groups = {
        entry["group"] for args, _, _ in scored for entry in args[1]
    }
    assert not scored_groups & restricted
    splittable = set(folds["groups"]) - restricted
    assert scored_groups == splittable


def test_the_refit_holds_every_photograph(monkeypatch, cfg, folds):
    matrices = _spy(monkeypatch, "_patch_matrix")
    release.release_fit(cfg, folds, model_version="test", featuriser=featuriser_at(1.0))

    refit_entries = matrices[-1][0][0]
    paths = [entry["path"] for entry in refit_entries]
    assert len(paths) == len(set(paths))
    assert sorted(paths) == sorted(_every_path(folds))
    assert _train_only_groups(folds) <= {entry["group"] for entry in refit_entries}


def test_the_release_contract_reproduces_the_refit(cfg, folds):
    fitted = release.release_fit(
        cfg, folds, model_version="test", featuriser=featuriser_at(1.0)
    )
    rng = np.random.default_rng(5)
    for _ in range(5):
        patches = rng.normal(0.0, 2.0, size=(int(rng.integers(1, 26)), WIDTH))
        np.testing.assert_allclose(
            evaluate(fitted.contract, patches),
            fitted.pipeline.predict_proba(patches).mean(axis=0),
            rtol=RELATIVE,
            atol=ABSOLUTE,
        )
    assert fitted.contract["dataset_version"] == "v-fixture"
    assert fitted.contract["model_version"] == "test"


def test_the_release_records_its_provenance(tmp_path, cfg, folds):
    fitted = release.release_fit(
        cfg, folds, model_version="test", featuriser=featuriser_at(1.0)
    )
    directory = release.write_release(fitted, tmp_path / "release")

    assert json.loads((directory / "spec.json").read_text(encoding="utf-8")) == fitted.contract
    selection = json.loads((directory / "selection.json").read_text(encoding="utf-8"))
    assert selection == fitted.selection
    assert selection["manifest_digest"] == "0" * 64
    assert selection["dataset_version"] == "v-fixture"
    assert selection["model_version"] == "test"
    assert selection["photographs"] == len(_every_path(folds))
    assert selection["groups"] == len(folds["groups"])
    assert selection["train_only_groups"] == len(_train_only_groups(folds))
    assert selection["criterion"]
    assert selection["chosen_c"] in C_GRID


def test_the_committed_release_is_a_valid_contract(cfg):
    if not COMMITTED_RELEASE.exists():
        pytest.fail(
            f"{COMMITTED_RELEASE} is missing; run `cd ml && python -m src.release "
            "--version v1 --model-version <version>` and "
            "`bash ml/scripts/deploy_to_app.sh v1`"
        )
    committed = json.loads(COMMITTED_RELEASE.read_text(encoding="utf-8"))

    # Everything but the fitted numbers and the version is what the writer puts
    # into any contract under this configuration.
    rng = np.random.default_rng(0)
    labels = np.repeat(np.arange(len(cfg["classes"])), 10)
    reference = descriptor_contract(
        fit_probe(rng.normal(size=(len(labels), WIDTH)) + labels[:, None], labels, c=1.0),
        cfg,
        model_version=committed["model_version"],
        dataset_version="v1",
    )
    for key in reference:
        if key not in ("standardiser", "regression"):
            assert committed[key] == reference[key], key

    classes = len(cfg["classes"])
    assert len(committed["standardiser"]["mean"]) == WIDTH
    assert len(committed["standardiser"]["scale"]) == WIDTH
    assert all(value > 0.0 for value in committed["standardiser"]["scale"])
    assert np.asarray(committed["regression"]["coefficients"]).shape == (classes, WIDTH)
    assert len(committed["regression"]["intercepts"]) == classes
