"""The field study (SPEC 0175): four arms, each soil sample held out in turn,
scored on its own unaugmented photographs, with the archive guarded.

The study is driven with fake featurisers over synthetic entries, as
`test_release.py` drives the release fit, so nothing decodes an image except
the end-to-end test, which builds a real export and archive on disk.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from src import field, field_study
from src.config import load_config
from src.dataset import create_folds, fold_split
from src.descriptors import feature_names

WIDTH = len(feature_names())


def _seed_of(path: str) -> int:
    return int.from_bytes(
        hashlib.blake2b(path.encode("utf-8"), digest_size=8).digest(), "big"
    )


def _fake(separation=2.0):
    """Patches around a class centre read from the source file's name."""

    def featurise(entry, cfg):
        source = entry.get("image", entry["path"])
        name = Path(source).stem.split("-")[0].replace("_", " ")
        generator = np.random.default_rng(_seed_of(entry["path"]) % (2**32))
        centre = np.zeros(WIDTH)
        centre[cfg["classes"].index(name)] = separation
        return centre + generator.normal(0.0, 1.0, size=(3, WIDTH))

    return featurise


@pytest.fixture
def cfg():
    return load_config()


def _field_entries(cfg, samples):
    """Three photographs per sample, the last of each upsampled."""
    entries = []
    for sample, name in samples:
        for index in range(3):
            slug = name.replace(" ", "_")
            entries.append(
                {
                    "path": f"/field/{slug}-{sample}-{index}.png",
                    "image": f"/field/{slug}-{sample}-{index}.png",
                    "class": name,
                    "label": cfg["classes"].index(name),
                    "group": sample,
                    "sample": sample,
                    "upsampled": index == 2,
                    "centre_y": 50.0,
                    "centre_x": 50.0,
                    "diameter": 90.0,
                }
            )
    return entries


def _archive_manifest(tmp_path, cfg, groups_per_class=4):
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
    )


def _archive(manifest):
    return [e for side in fold_split(manifest, 0, 0).values() for e in side]


SAMPLES = [
    ("S1", "Argilosa"),
    ("S2", "Muito Argilosa"),
    ("S3", "Media"),
    ("S4", "Arenosa"),
    ("S5", "Argilosa"),
]


def test_variants_are_entries_of_their_own():
    entry = {"path": "/a.png", "label": 0, "group": "g"}
    variants = field_study.variants_of([entry], 3)

    assert [v["path"] for v in variants] == ["/a.png::aug0", "/a.png::aug1", "/a.png::aug2"]
    assert all(v["image"] == "/a.png" for v in variants)
    assert [v["variant"] for v in variants] == [0, 1, 2]


def test_the_held_out_soil_never_trains(tmp_path, cfg):
    field_entries = _field_entries(cfg, SAMPLES)
    archive = _archive(_archive_manifest(tmp_path, cfg))
    for held_out in ("S1", "S2", "S3", "S4", "S5"):
        for arm in field_study.ARMS:
            train, test = field_study.held_out_sides(
                arm, archive, field_entries, held_out, variants=2
            )
            assert all(e.get("sample") != held_out for e in train), (arm, held_out)
            assert {e["sample"] for e in test} == {held_out}


def test_scoring_uses_unaugmented_photographs(tmp_path, cfg):
    field_entries = _field_entries(cfg, SAMPLES)
    archive = _archive(_archive_manifest(tmp_path, cfg))

    _, test = field_study.held_out_sides("A3", archive, field_entries, "S3", variants=4)

    assert [e["path"] for e in test] == [
        e["path"] for e in field_entries if e["sample"] == "S3"
    ]
    assert all("variant" not in e for e in test)


def test_the_archive_guard_trains_augmented_and_tests_plain(tmp_path, cfg):
    manifest = _archive_manifest(tmp_path, cfg)
    field_entries = _field_entries(cfg, SAMPLES)
    for arm in field_study.ARMS:
        for train, test in field_study.archive_guard_sides(
            arm, manifest, field_entries, variants=2
        ):
            augmented = any("variant" in e for e in train)
            assert augmented == (arm in ("A1", "A2", "A3")), arm
            assert all("variant" not in e for e in test), arm
            assert all(e.get("sample") is None for e in test), arm
            archive_variants = [e for e in train if "variant" in e and "sample" not in e]
            assert bool(archive_variants) == (arm in ("A1", "A3")), arm


def test_c_is_the_releases(tmp_path):
    release = tmp_path / "v1" / "release"
    release.mkdir(parents=True)
    (release / "selection.json").write_text(json.dumps({"chosen_c": 10.0}))

    assert field_study.release_c(tmp_path, "v1") == 10.0
    with pytest.raises(FileNotFoundError, match="python -m src.release"):
        field_study.release_c(tmp_path, "v2")


@pytest.mark.parametrize(
    ("field_gain", "archive_loss", "adoptable"),
    [(0.20, 0.02, True), (0.19, 0.0, False), (0.30, 0.021, False)],
)
def test_the_adoption_rule_is_applied_as_written(field_gain, archive_loss, adoptable):
    baseline = {"field_macro": 0.25, "archive": 0.70}
    arm = {
        "field_macro": 0.25 + field_gain,
        "archive": 0.70 - archive_loss,
    }

    assert field_study.adoptable(arm, baseline) is adoptable


def test_upsampled_photographs_are_reported_apart(tmp_path, cfg):
    report = field_study.run_study(
        cfg,
        _archive_manifest(tmp_path, cfg),
        _field_entries(cfg, SAMPLES),
        c=1.0,
        archive_featuriser=_fake(),
        field_featuriser=_fake(),
        variants=2,
    )

    for arm in field_study.ARMS:
        scores = report["arms"][arm]
        assert scores["field"]["all"]["photographs"] == 15
        assert scores["field"]["native"]["photographs"] == 10
        assert set(scores["field"]["per_sample"]) == {s for s, _ in SAMPLES}
        assert "archive" in scores


def _write_png(path: Path, level: int, seed: int) -> None:
    generator = np.random.default_rng(seed)
    pixels = np.clip(
        generator.normal(level, 30.0, size=(560, 560, 3)), 0, 255
    ).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(pixels, mode="RGB").save(path)


def test_the_study_runs_end_to_end(tmp_path, cfg):
    export = tmp_path / "export"
    rows = []
    for index, (sample, name) in enumerate(SAMPLES[:3]):
        for photo in range(2):
            file = f"{sample}_{photo}.png"
            _write_png(export / file, 60 + 40 * index, seed=index * 10 + photo)
            rows.append(
                {
                    "file": file,
                    "class": name,
                    "sample": sample,
                    "source": f"{sample}_{photo}.jpg",
                    "measured_mm_per_px": 0.1,
                    "canonical_mm_per_px": cfg["preprocessing"]["canonical_mm_per_px"],
                    "centre_y": 280.0,
                    "centre_x": 280.0,
                    "diameter": 500.0,
                    "upsampled": photo == 1,
                }
            )
    (export / "manifest.json").write_text(json.dumps(rows))

    entries = field.load_field_export(export, cfg)
    assert [e["sample"] for e in entries] == ["S1", "S1", "S2", "S2", "S3", "S3"]
    block = field.field_features(entries[0], cfg)
    assert block.shape[1] == WIDTH and len(block) >= 1
    augmented = field.field_features({**entries[0], "path": "x::aug1", "variant": 1}, cfg)
    assert augmented.shape == block.shape
    assert not np.allclose(augmented, block)

    report = field_study.run_study(
        cfg,
        _archive_manifest(tmp_path, cfg),
        entries,
        c=1.0,
        archive_featuriser=_fake(),
        field_featuriser=field.field_features,
        variants=1,
    )
    out = field_study.write_report(report, tmp_path / "field_study")
    written = json.loads(out.read_text())
    assert set(written["arms"]) == set(field_study.ARMS)
    assert set(written["arms"]["A0"]["field"]["per_sample"]) == {"S1", "S2", "S3"}
    assert "adoptable" in written and "preferred" in written
