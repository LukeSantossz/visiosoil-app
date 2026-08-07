"""Tests for dataset scanning, splitting, class ordering, and data leakage."""

import json
import tempfile
from pathlib import Path

import pytest
from PIL import Image

from src.dataset import (
    scan_dataset,
    create_splits,
    verify_images,
    _extract_sample_id,
    _group_id,
)


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

    leaks = _leaked_groups(manifest)
    assert not leaks, f"Sample groups leaked between splits: {leaks}"


def _leaked_groups(manifest: dict) -> dict:
    """Groups appearing in more than one split, keyed by the split pair.

    Compares the key `create_splits` actually groups by. Comparing the bare
    `_extract_sample_id` stem instead would report a leak for any two classes
    that happen to number their samples the same way, which is a naming
    coincidence and not a shared physical sample: one soil sample carries one
    laboratory texture class, so it lives in exactly one class folder.
    """
    per_split = {
        name: {
            _group_id(entry["class"], _extract_sample_id(entry["path"]))
            for entry in manifest["splits"][name]
        }
        for name in ("train", "val", "test")
    }

    leaks = {}
    for a, b in (("train", "val"), ("train", "test"), ("val", "test")):
        overlap = per_split[a] & per_split[b]
        if overlap:
            leaks[f"{a}/{b}"] = overlap
    return leaks


def test_leakage_check_still_catches_a_real_leak():
    """A group forced into two splits must be reported.

    Without this, correcting the assertion above could have turned it into a
    check that passes unconditionally.
    """
    shared = {"path": "/raw/Arenosa/lab_77 (1).jpg", "class": "Arenosa", "label": 0}
    manifest = {
        "splits": {
            "train": [shared, {"path": "/raw/Media/lab_12.jpg", "class": "Media", "label": 1}],
            "val": [{"path": "/raw/Arenosa/lab_77 (2).jpg", "class": "Arenosa", "label": 0}],
            "test": [],
        }
    }

    leaks = _leaked_groups(manifest)
    assert "train/val" in leaks
    assert leaks["train/val"] == {_group_id("Arenosa", "lab_77")}


# --- SPEC 0032: the dataset is verified before training, not during it -----


def _write_image(path: Path, size=(16, 16)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, (120, 90, 60)).save(path, format="JPEG")


def test_verify_accepts_readable_images(tmp_path):
    paths = [tmp_path / f"soil_{i}.jpg" for i in range(3)]
    for path in paths:
        _write_image(path)

    verify_images({"Arenosa": [str(p) for p in paths]})


def test_verify_names_the_unreadable_file(tmp_path):
    good = tmp_path / "good.jpg"
    _write_image(good)
    bad = tmp_path / "truncated.jpg"
    bad.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)

    with pytest.raises(ValueError, match="truncated.jpg"):
        verify_images({"Arenosa": [str(good), str(bad)]})


def test_verify_names_every_unreadable_file(tmp_path):
    """One run must tell the operator everything to fix."""
    bad_names = ["a.jpg", "b.jpg", "c.jpg"]
    for name in bad_names:
        (tmp_path / name).write_bytes(b"not an image")

    with pytest.raises(ValueError) as raised:
        verify_images({"Arenosa": [str(tmp_path / n) for n in bad_names]})

    message = str(raised.value)
    for name in bad_names:
        assert name in message


def test_verify_reports_a_missing_file(tmp_path):
    with pytest.raises(ValueError, match="absent.jpg"):
        verify_images({"Arenosa": [str(tmp_path / "absent.jpg")]})


def test_verify_rejects_a_format_the_training_decoder_cannot_read(tmp_path):
    """Verification must use the decoder training uses, not a more tolerant one.

    Pillow identifies a file by sniffing its content, so it happily reads TIFF
    bytes stored under a `.png` name. `scan_dataset` admits the file on its
    extension, and `tf.io.decode_image` — the decoder `_parse_image` actually
    uses — rejects it: "Unknown image file format. One of JPEG, JPEG XL, PNG,
    GIF, BMP, WebP required."

    So a Pillow-based check reports a clean dataset and training dies partway
    through an epoch, which is precisely the failure the fail-loud requirement
    exists to prevent. Mislabelled files are not exotic; they are what a
    conversion or a rename produces.
    """
    mislabelled = tmp_path / "sample.png"
    Image.new("RGB", (16, 16), (120, 90, 60)).save(mislabelled, format="TIFF")

    # Pillow reads it, so a Pillow-based check would report no problem at all.
    with Image.open(mislabelled) as probe:
        probe.load()

    with pytest.raises(ValueError, match="sample.png"):
        verify_images({"Arenosa": [str(mislabelled)]})
