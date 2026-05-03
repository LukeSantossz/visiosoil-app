"""Tests for dataset scanning, splitting, class ordering, and data leakage."""

import json
import tempfile
from pathlib import Path

import pytest

from src.dataset import scan_dataset, create_splits, _extract_sample_id


@pytest.fixture
def fake_dataset(tmp_path):
    """Create a fake raw dataset with 5 classes, 10 singleton images each."""
    classes = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]
    raw_dir = tmp_path / "raw"
    for cls in classes:
        folder = raw_dir / cls.replace(" ", "_")
        folder.mkdir(parents=True)
        # 10 singleton images = 10 groups per class (enough for stratified split)
        for i in range(10):
            (folder / f"img_{i}.jpg").write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)
    return str(raw_dir), classes


@pytest.fixture
def grouped_dataset(tmp_path):
    """Create a dataset with multi-photo sample groups per class."""
    classes = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]
    raw_dir = tmp_path / "raw"
    for cls in classes:
        folder = raw_dir / cls.replace(" ", "_")
        folder.mkdir(parents=True)
        # 8 sample groups, 3 photos each = 24 images per class
        for group in range(8):
            for photo in range(3):
                name = f"sample_{group} ({photo}).jpg"
                (folder / name).write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)
    return str(raw_dir), classes


def test_create_splits_preserves_config_order(fake_dataset):
    """create_splits must use class order from input dict, not sorted()."""
    raw_dir, classes = fake_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    create_splits(class_images, val_split=0.15, test_split=0.15, seed=42, splits_dir=splits_dir)

    with open(Path(splits_dir) / "splits.json") as f:
        manifest = json.load(f)

    assert manifest["classes"] == classes, (
        f"splits.json classes {manifest['classes']} != config classes {classes}"
    )
    assert manifest["class_to_idx"] == {c: i for i, c in enumerate(classes)}


def test_create_splits_labels_match_class_to_idx(fake_dataset):
    """Each entry's label must match class_to_idx for its class name."""
    raw_dir, classes = fake_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    create_splits(class_images, val_split=0.15, test_split=0.15, seed=42, splits_dir=splits_dir)

    with open(Path(splits_dir) / "splits.json") as f:
        manifest = json.load(f)

    class_to_idx = manifest["class_to_idx"]
    for split_name in ("train", "val", "test"):
        for entry in manifest["splits"][split_name]:
            assert entry["label"] == class_to_idx[entry["class"]], (
                f"Entry {entry} has mismatched label in {split_name}"
            )


def test_scan_dataset_preserves_config_order(fake_dataset):
    """scan_dataset returns keys in config order."""
    raw_dir, classes = fake_dataset
    result = scan_dataset(raw_dir, classes)
    assert list(result.keys()) == classes


def test_extract_sample_id_grouped():
    """_extract_sample_id extracts prefix from 'name (N).ext' pattern."""
    assert _extract_sample_id("/data/100147,21 (6).JPG") == "100147,21"
    assert _extract_sample_id("/data/100147,21 (7).JPG") == "100147,21"
    assert _extract_sample_id("/data/sample_3 (1).jpg") == "sample_3"


def test_extract_sample_id_singleton():
    """_extract_sample_id returns stem for single-image files."""
    assert _extract_sample_id("/data/single_image.jpg") == "single_image"


def test_create_splits_persists_fractions(fake_dataset):
    """splits.json must persist val_split and test_split fractions."""
    raw_dir, classes = fake_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    create_splits(class_images, val_split=0.15, test_split=0.15, seed=42, splits_dir=splits_dir)

    with open(Path(splits_dir) / "splits.json") as f:
        manifest = json.load(f)

    assert manifest["val_split"] == 0.15
    assert manifest["test_split"] == 0.15


def test_create_splits_rejects_too_few_groups(tmp_path):
    """create_splits raises ValueError when a class has fewer than 3 groups."""
    classes = ["A", "B"]
    raw_dir = tmp_path / "raw"
    for cls in classes:
        folder = raw_dir / cls
        folder.mkdir(parents=True)
        # Only 2 singleton images = 2 groups (below minimum of 3)
        for i in range(2):
            (folder / f"img_{i}.jpg").write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)

    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    with pytest.raises(ValueError, match="at least 3"):
        create_splits(class_images, val_split=0.15, test_split=0.15, seed=42, splits_dir=splits_dir)


def test_no_sample_leakage_between_splits(grouped_dataset):
    """No sample group should appear in more than one split."""
    raw_dir, classes = grouped_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    create_splits(class_images, val_split=0.15, test_split=0.15, seed=42, splits_dir=splits_dir)

    with open(Path(splits_dir) / "splits.json") as f:
        manifest = json.load(f)

    # Collect sample IDs per split
    split_sample_ids = {}
    for split_name in ("train", "val", "test"):
        ids = set()
        for entry in manifest["splits"][split_name]:
            ids.add(_extract_sample_id(entry["path"]))
        split_sample_ids[split_name] = ids

    # No overlap between any pair of splits
    for a, b in [("train", "val"), ("train", "test"), ("val", "test")]:
        overlap = split_sample_ids[a] & split_sample_ids[b]
        assert not overlap, (
            f"Sample IDs leaked between {a} and {b}: {overlap}"
        )
