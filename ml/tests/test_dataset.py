"""Tests for dataset scanning, fold generation, class ordering, and leakage.

The folder-scan path predates the manifest and is what these cover; the
manifest-backed contract is `test_manifest_splits.py`, and the protocol's own
criteria are `test_folds.py`. SPEC 0042 replaced the single three-way split with
repeated group k-fold, so what was asserted about `create_splits` here is
asserted about `create_folds`.
"""

import json
import tempfile
from pathlib import Path

import pytest
from PIL import Image

from src.dataset import (
    FOLD_MANIFEST_FILENAME,
    create_folds,
    fold_split,
    sample_id_from_filename,
    scan_dataset,
    verify_images,
    _group_id,
)
from tests.support import requires_tensorflow

K = 5
REPEATS = 2


def generate(class_images, splits_dir, *, k=K, repeats=REPEATS):
    """Generate folds over a folder-scanned dataset and return the manifest."""
    return create_folds(
        class_images, k=k, repeats=repeats, seed=42, splits_dir=splits_dir
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


def test_create_folds_preserves_config_order(fake_dataset):
    """create_folds must use class order from input dict, not sorted()."""
    raw_dir, classes = fake_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    generate(class_images, splits_dir)

    with open(Path(splits_dir) / FOLD_MANIFEST_FILENAME) as f:
        manifest = json.load(f)

    assert manifest["classes"] == classes, (
        f"splits.json classes {manifest['classes']} != config classes {classes}"
    )
    assert manifest["class_to_idx"] == {c: i for i, c in enumerate(classes)}


def test_create_folds_labels_match_class_to_idx(fake_dataset):
    """Each entry's label must match class_to_idx for its class name."""
    raw_dir, classes = fake_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    folds = generate(class_images, splits_dir)

    class_to_idx = folds["class_to_idx"]
    for repeat in range(REPEATS):
        for fold in range(K):
            split = fold_split(folds, repeat, fold)
            for side in ("train", "test"):
                for entry in split[side]:
                    assert entry["label"] == class_to_idx[entry["class"]], (
                        f"Entry {entry} has mismatched label in {side}"
                    )


def test_scan_dataset_preserves_config_order(fake_dataset):
    """scan_dataset returns keys in config order."""
    raw_dir, classes = fake_dataset
    result = scan_dataset(raw_dir, classes)
    assert list(result.keys()) == classes


def test_sample_id_from_filename_grouped():
    """sample_id_from_filename extracts prefix from 'name (N).ext' pattern."""
    assert sample_id_from_filename("/data/100147,21 (6).JPG") == "100147,21"
    assert sample_id_from_filename("/data/100147,21 (7).JPG") == "100147,21"
    assert sample_id_from_filename("/data/sample_3 (1).jpg") == "sample_3"


def test_sample_id_from_filename_singleton():
    """sample_id_from_filename returns stem for single-image files."""
    assert sample_id_from_filename("/data/single_image.jpg") == "single_image"


def test_create_folds_rejects_a_class_below_the_fold_count(tmp_path):
    """The floor is k, which is what puts a group of every class in every fold."""
    classes = ["A", "B"]
    raw_dir = tmp_path / "raw"
    for cls in classes:
        folder = raw_dir / cls
        folder.mkdir(parents=True)
        # Four singleton images = four groups, below k = 5.
        for i in range(4):
            (folder / f"img_{i}.jpg").write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)

    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    with pytest.raises(ValueError, match="at least 5"):
        generate(class_images, splits_dir)


def test_no_sample_leakage_between_a_folds_two_sides(grouped_dataset):
    """No sample group may be both trained on and scored in one fold."""
    raw_dir, classes = grouped_dataset
    class_images = scan_dataset(raw_dir, classes)
    splits_dir = tempfile.mkdtemp()

    folds = generate(class_images, splits_dir)

    for repeat in range(REPEATS):
        for fold in range(K):
            leaks = _leaked_groups(fold_split(folds, repeat, fold))
            assert not leaks, (
                f"repeat {repeat} fold {fold} leaked sample groups: {leaks}"
            )


def _leaked_groups(split: dict) -> set:
    """Groups appearing on both sides of one fold.

    Compares the key `create_folds` actually groups by, rebuilt from the file
    path. Comparing the bare `sample_id_from_filename` stem instead would report
    a leak for any two classes that happen to number their samples the same way,
    which is a naming coincidence and not a shared physical sample: one soil
    sample carries one laboratory texture class, so it lives in exactly one
    class folder.
    """
    per_side = {
        name: {
            _group_id(entry["class"], sample_id_from_filename(entry["path"]))
            for entry in split[name]
        }
        for name in ("train", "test")
    }
    return per_side["train"] & per_side["test"]


def test_leakage_check_still_catches_a_real_leak():
    """A group forced onto both sides must be reported.

    Without this, correcting the assertion above could have turned it into a
    check that passes unconditionally.
    """
    shared = {"path": "/raw/Arenosa/lab_77 (1).jpg", "class": "Arenosa", "label": 0}
    split = {
        "train": [
            shared,
            {"path": "/raw/Media/lab_12.jpg", "class": "Media", "label": 1},
        ],
        "test": [{"path": "/raw/Arenosa/lab_77 (2).jpg", "class": "Arenosa", "label": 0}],
    }

    assert _leaked_groups(split) == {_group_id("Arenosa", "lab_77")}


# --- SPEC 0032: the dataset is verified before training, not during it -----


def _write_image(path: Path, size=(16, 16)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, (120, 90, 60)).save(path, format="JPEG")


@requires_tensorflow
def test_verify_accepts_readable_images(tmp_path):
    paths = [tmp_path / f"soil_{i}.jpg" for i in range(3)]
    for path in paths:
        _write_image(path)

    verify_images({"Arenosa": [str(p) for p in paths]})


@requires_tensorflow
def test_verify_names_the_unreadable_file(tmp_path):
    good = tmp_path / "good.jpg"
    _write_image(good)
    bad = tmp_path / "truncated.jpg"
    bad.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 100)

    with pytest.raises(ValueError, match="truncated.jpg"):
        verify_images({"Arenosa": [str(good), str(bad)]})


@requires_tensorflow
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


@requires_tensorflow
def test_verify_reports_a_missing_file(tmp_path):
    with pytest.raises(ValueError, match="absent.jpg"):
        verify_images({"Arenosa": [str(tmp_path / "absent.jpg")]})


@requires_tensorflow
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
