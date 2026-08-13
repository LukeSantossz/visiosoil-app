"""Tests for splits generated from a manifest (SPEC 0033).

Separate from ``test_dataset.py``, which covers the folder-scan path that
predates the manifest. What is asserted here is the manifest-backed contract:
grouping comes from the ``sample_id`` column rather than from a filename
pattern, and a split records which dataset version and which manifest it was
generated from.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from src.dataset import create_splits, load_splits
from src.manifest import (
    class_images,
    manifest_digest,
    read_manifest,
    sample_ids_by_image,
)

CLASSES = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]

#: Nothing here decodes an image, so a marker byte string is all the
#: manifest-to-disk check needs.
PLACEHOLDER_IMAGE_BYTES = b"dataset fixture image"

MANIFEST_COLUMNS = (
    "sample_id",
    "texture_class",
    "image",
    "setting",
    "site",
    "device",
    "captured_at",
)

#: Eight paired samples per class. Both stratified cuts then hold at least one
#: group of every class, which is what scikit-learn requires of each side.
SAMPLES_PER_CLASS = 8


def write_version(tmp_path, extra_photographs=0):
    """Write a manifest-backed dataset version and return its root."""
    root = tmp_path / "datasets" / "v1"
    (root / "images").mkdir(parents=True)
    rows = []

    def add(sample_id, texture_class, suffix, setting, site):
        relative = "images/{}_{}.jpg".format(sample_id, suffix)
        (root / relative).write_bytes(PLACEHOLDER_IMAGE_BYTES)
        rows.append(
            {
                "sample_id": sample_id,
                "texture_class": texture_class,
                "image": relative,
                "setting": setting,
                "site": site,
                "device": "Pixel 8",
                "captured_at": "2026-08-12",
            }
        )

    for texture_class in CLASSES:
        prefix = texture_class.replace(" ", "_")
        for index in range(SAMPLES_PER_CLASS):
            sample_id = "{}-{}".format(prefix, index)
            site = "Fazenda {}".format(index % 2)
            add(sample_id, texture_class, "dish", "dish", site)
            add(sample_id, texture_class, "paper", "paper", site)

    for extra in range(extra_photographs):
        add("Arenosa-0", "Arenosa", "dish{}".format(extra + 2), "dish", "Fazenda 0")

    lines = [",".join(MANIFEST_COLUMNS)]
    lines += [
        ",".join(str(row[column]) for column in MANIFEST_COLUMNS) for row in rows
    ]
    (root / "manifest.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return root


def generate(tmp_path, root, *, with_provenance=True):
    """Generate splits from the manifest at ``root`` and return them."""
    manifest = read_manifest(root, CLASSES)
    splits_dir = tmp_path / "splits"
    splits = create_splits(
        class_images(manifest, CLASSES),
        val_split=0.15,
        test_split=0.15,
        seed=42,
        splits_dir=str(splits_dir),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version if with_provenance else None,
        manifest_digest=manifest.digest if with_provenance else None,
    )
    return manifest, splits_dir, splits


def photographs_of(splits, stem_prefix):
    """Return the split names holding a sample, and how many rows it has."""
    holders = set()
    count = 0
    for name, entries in splits.items():
        for entry in entries:
            if Path(entry["path"]).name.startswith(stem_prefix):
                holders.add(name)
                count += 1
    return holders, count


def test_splits_group_by_sample_id(tmp_path):
    """Every photograph of one physical sample lands in exactly one split."""
    root = write_version(tmp_path, extra_photographs=1)

    _, _, splits = generate(tmp_path, root)

    holders, count = photographs_of(splits, "Arenosa-0_")
    assert count == 3
    assert len(holders) == 1


def test_splits_group_on_the_column_not_the_filename(tmp_path):
    """Two files with unrelated names group together when the column says so."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    grouping = sample_ids_by_image(manifest)
    assert len(set(grouping.values())) == len(CLASSES) * SAMPLES_PER_CLASS

    _, _, splits = generate(tmp_path, root)

    holders, count = photographs_of(splits, "Media-3_")
    assert count == 2
    assert len(holders) == 1


def test_splits_record_the_dataset_version_and_manifest_hash(tmp_path):
    """A split carries the provenance that makes it checkable."""
    root = write_version(tmp_path)

    manifest, splits_dir, _ = generate(tmp_path, root)

    with open(splits_dir / "splits.json") as handle:
        written = json.load(handle)
    assert written["dataset_version"] == manifest.version == "v1"
    assert written["manifest_digest"] == manifest_digest(root)


def test_loading_a_split_whose_hash_does_not_match_fails(tmp_path):
    """Splits generated before the manifest changed must not be reused."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)

    with pytest.raises(ValueError, match="manifest_digest"):
        load_splits(str(splits_dir), manifest_digest="0" * 64)


def test_loading_a_split_whose_hash_matches_succeeds(tmp_path):
    """The matching case loads, so the check is a guard rather than a wall."""
    root = write_version(tmp_path)
    manifest, splits_dir, _ = generate(tmp_path, root)

    loaded = load_splits(str(splits_dir), manifest_digest=manifest.digest)

    assert loaded["dataset_version"] == "v1"


def test_loading_a_split_without_provenance_fails_when_a_hash_is_required(tmp_path):
    """A split predating this schema cannot be shown to match anything."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root, with_provenance=False)

    with pytest.raises(ValueError, match="manifest_digest"):
        load_splits(str(splits_dir), manifest_digest=manifest_digest(root))


def test_loading_a_split_without_a_required_hash_still_works(tmp_path):
    """The folder-scan path passes no digest, so it must keep loading."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root, with_provenance=False)

    assert load_splits(str(splits_dir))["classes"] == CLASSES


def test_importing_dataset_does_not_load_tensorflow():
    """Validating a dataset must not require the training stack installed.

    The protocol is written so a collector can execute and check it without this
    terminal present, and ``scripts/validate_dataset.py`` imports this module.
    """
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import src.dataset, sys; "
            "assert 'tensorflow' not in sys.modules, 'dataset imported tensorflow'",
        ],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
    )

    assert completed.returncode == 0, completed.stderr
