"""Tests for SPEC 0040: ingesting the delivered archive as a dataset version.

The archive is source material with English folder names, three capture
populations and a container neither pipeline decodes. Every case here builds a
miniature archive of the same shape in a temporary directory, so the suite runs
without the real delivery present. Two cases additionally assert against the
real version when it exists locally, and skip in CI, where the images are not
tracked.
"""

import csv
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image
from pillow_heif import register_heif_opener

from src.ingest import (
    ARCHIVE_CLASS_BY_FOLDER,
    BURST_GAP_SECONDS,
    UNKNOWN,
    ArchiveError,
    ingest_archive,
    scan_archive,
)
from src.manifest import (
    PROVENANCE_COLUMNS,
    TRAIN_ONLY_SOURCE_GROUPS,
    derived_sample_ids,
    ManifestError,
    read_manifest,
    sample_ids_by_image,
    train_only_sample_ids,
    read_manifest_or_none,
)

register_heif_opener()

CLASSES = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]

#: Enough texture that a PNG round-trip is a real comparison rather than a
#: comparison of two flat fields.
SIDE_PX = 48


def _image(seed):
    pixels = np.random.default_rng(seed).integers(0, 255, (SIDE_PX, SIDE_PX, 3), dtype=np.uint8)
    return Image.fromarray(pixels, mode="RGB")


def _exif(model="iPhone 11", when="2023:10:04 09:15:00"):
    exif = Image.Exif()
    exif[0x0110] = model  # Model
    exif[0x0132] = when  # DateTime
    return exif


def write_archive(tmp_path):
    """A miniature archive holding all three capture populations.

    Group C is HEIC with EXIF, group A is JPEG with EXIF, group B is JPEG with
    none. The bare-plus-parenthesised pair that only group B exhibits is here
    too, because it is what decides the sample count.
    """
    root = tmp_path / "archive"
    for folder in ARCHIVE_CLASS_BY_FOLDER:
        (root / folder).mkdir(parents=True)

    # Group C: HEIC, EXIF, two photographs of one sample.
    for index in (1, 2):
        _image(index).save(
            root / "1 Sandy" / f"100262,1 ({index}).HEIC", exif=_exif(), quality=90
        )
    # Group A: JPEG, EXIF, one sample of two photographs, in another class.
    for index in (1, 2):
        _image(10 + index).save(
            root / "3 Medium" / f"112098-3 ({index}).JPEG",
            exif=_exif(when="2023:11:22 14:02:00"),
            quality=95,
        )
    # Group B: JPEG, no EXIF at all, the bare-plus-(2) pair, one sample.
    _image(21).save(root / "4 Clayey" / "119026_1.jpeg", quality=75)
    _image(22).save(root / "4 Clayey" / "119026_1 (2).jpeg", quality=75)
    # Two more group B samples, so the class has enough groups to split.
    for suffix in ("119026_2", "119026_3"):
        _image(hash(suffix) % 1000).save(root / "4 Clayey" / f"{suffix}.jpeg", quality=75)
    # Group C again, so two classes hold native material.
    for index in (1, 2):
        _image(30 + index).save(
            root / "5 Very Clayey" / f"113266-1 ({index}).HEIC", exif=_exif(), quality=90
        )
    # Siltosa exists in the archive and is kept in the version, per ADR 0016:
    # the first model drops it, the dataset does not.
    _image(41).save(root / "2 Silty" / "100999,1 (1).JPEG", exif=_exif(when="2023:11:22 14:30:00"), quality=95)
    return root


def rows_of(root):
    with (root / "manifest.csv").open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def ingest_into(tmp_path):
    source = write_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    report = ingest_archive(source, version, classes=CLASSES)
    return source, version, report


# --- Acceptance criterion 1 ------------------------------------------------


def test_ingest_archive_converts_every_heic_file_to_png(tmp_path):
    source, version, report = ingest_into(tmp_path)

    heic_count = len(list(source.rglob("*.HEIC")))
    assert heic_count == 4
    assert report.converted == heic_count

    converted = [row for row in rows_of(version) if row["source_format"] == "heic"]
    assert len(converted) == heic_count
    assert all(row["image"].endswith(".png") for row in converted)
    for row in converted:
        assert (version / row["image"]).is_file()


def test_ingest_archive_preserves_heic_pixels_through_the_conversion(tmp_path):
    source, version, _ = ingest_into(tmp_path)

    original = Image.open(source / "1 Sandy" / "100262,1 (1).HEIC").convert("RGB")
    row = next(
        row for row in rows_of(version) if row["image"].endswith("100262,1 (1).png")
    )
    converted = Image.open(version / row["image"]).convert("RGB")

    assert converted.size == original.size
    assert np.array_equal(np.asarray(converted), np.asarray(original))


# --- Acceptance criterion 2 ------------------------------------------------


def test_ingest_archive_copies_jpeg_files_unchanged(tmp_path):
    source, version, _ = ingest_into(tmp_path)

    for relative in ("3 Medium/112098-3 (1).JPEG", "4 Clayey/119026_1.jpeg"):
        original = source / relative
        row = next(
            row
            for row in rows_of(version)
            if Path(row["image"]).name == original.name
        )
        assert (version / row["image"]).read_bytes() == original.read_bytes()


# --- Acceptance criteria 3 and 4 -------------------------------------------


def test_ingest_archive_maps_folder_names_to_configured_classes(tmp_path):
    _, version, _ = ingest_into(tmp_path)

    by_name = {Path(row["image"]).name: row["texture_class"] for row in rows_of(version)}
    assert by_name["100262,1 (1).png"] == "Arenosa"
    assert by_name["112098-3 (1).JPEG"] == "Media"
    assert by_name["119026_1.jpeg"] == "Argilosa"
    assert by_name["113266-1 (1).png"] == "Muito Argilosa"
    assert by_name["100999,1 (1).JPEG"] == "Siltosa"


def test_ingest_archive_refuses_index_based_class_mapping(tmp_path):
    """`4 Clayey` is Argilosa, not the fourth configured class.

    `ml/config.yaml` orders the classes Arenosa, Media, Siltosa, Muito Argilosa,
    Argilosa, while the archive folders run in granulometric order. Pairing the
    folder number to the class index mislabels four of the five, silently.
    """
    assert CLASSES[3] == "Muito Argilosa"
    assert ARCHIVE_CLASS_BY_FOLDER["4 Clayey"] == "Argilosa"
    assert ARCHIVE_CLASS_BY_FOLDER["5 Very Clayey"] == "Muito Argilosa"
    assert list(ARCHIVE_CLASS_BY_FOLDER.values()) != CLASSES


def test_ingest_archive_refuses_a_folder_outside_the_map(tmp_path):
    source = write_archive(tmp_path)
    (source / "6 Peaty").mkdir()
    _image(99).save(source / "6 Peaty" / "x (1).JPEG", exif=_exif(), quality=95)

    with pytest.raises(ArchiveError) as excinfo:
        ingest_archive(source, tmp_path / "datasets" / "v1", classes=CLASSES)

    assert "6 Peaty" in str(excinfo.value)


def test_ingest_archive_refuses_an_unreadable_file_rather_than_skipping_it(tmp_path):
    source = write_archive(tmp_path)
    (source / "1 Sandy" / "broken (1).JPEG").write_bytes(b"not an image")

    with pytest.raises(ArchiveError) as excinfo:
        ingest_archive(source, tmp_path / "datasets" / "v1", classes=CLASSES)

    assert "broken (1).JPEG" in str(excinfo.value)


# --- Acceptance criterion 5 ------------------------------------------------


def test_manifest_declares_one_sample_group_for_a_bare_and_parenthesised_pair(tmp_path):
    _, version, _ = ingest_into(tmp_path)

    by_name = {Path(row["image"]).name: row["sample_id"] for row in rows_of(version)}
    assert by_name["119026_1.jpeg"] == by_name["119026_1 (2).jpeg"] == "119026_1"
    assert by_name["100262,1 (1).png"] == by_name["100262,1 (2).png"] == "100262,1"


def test_manifest_does_not_group_by_the_lab_batch_number(tmp_path):
    """`116520_1` and `116520_2` are different soils under one batch number."""
    source = write_archive(tmp_path)
    _image(51).save(source / "3 Medium" / "116520_1.jpeg", quality=75)
    _image(52).save(source / "4 Clayey" / "116520_2.jpeg", quality=75)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)

    by_name = {Path(row["image"]).name: row["sample_id"] for row in rows_of(version)}
    assert by_name["116520_1.jpeg"] != by_name["116520_2.jpeg"]


# --- Acceptance criterion 6 ------------------------------------------------


def test_manifest_records_unknown_rather_than_a_guess(tmp_path):
    _, version, _ = ingest_into(tmp_path)
    rows = rows_of(version)

    assert {row["site"] for row in rows} == {UNKNOWN}

    group_b = [row for row in rows if row["source_group"] == "B"]
    assert group_b, "the fixture archive must hold a group B population"
    assert {row["captured_at"] for row in group_b} == {UNKNOWN}
    assert {row["device"] for row in group_b} == {UNKNOWN}

    dated = [row for row in rows if row["source_group"] in ("A", "C")]
    assert {row["device"] for row in dated} == {"iphone-11"}
    assert {row["captured_at"] for row in dated} == {"2023-10-04", "2023-11-22"}


# --- Acceptance criterion 8 ------------------------------------------------


def test_manifest_records_source_format_group_and_dimensions_per_row(tmp_path):
    _, version, _ = ingest_into(tmp_path)
    rows = rows_of(version)

    for column in PROVENANCE_COLUMNS:
        assert column in rows[0], column

    assert {row["source_group"] for row in rows} == {"A", "B", "C"}
    assert {row["source_format"] for row in rows} == {"heic", "jpeg"}
    assert all(int(row["source_width"]) == SIDE_PX for row in rows)
    assert all(int(row["source_height"]) == SIDE_PX for row in rows)


def test_source_group_is_read_from_evidence_not_from_the_filename_case(tmp_path):
    """A JPEG is group A when it carries EXIF and group B when it does not.

    The delivered archive happens to spell one population `.JPEG` and the other
    `.jpeg`, but a filesystem that folds case would erase that distinction and
    the populations differ in what they actually contain, not in how they are
    spelled.
    """
    source = tmp_path / "archive"
    (source / "1 Sandy").mkdir(parents=True)
    _image(1).save(source / "1 Sandy" / "a (1).jpeg", exif=_exif(), quality=95)
    _image(2).save(source / "1 Sandy" / "b (1).JPEG", quality=75)

    scanned = {image.path.name: image.source_group for image in scan_archive(source)}
    assert scanned["a (1).jpeg"] == "A"
    assert scanned["b (1).JPEG"] == "B"


# --- Acceptance criterion 10 and 11 ----------------------------------------


def test_train_only_sample_ids_names_every_group_b_sample(tmp_path):
    _, version, _ = ingest_into(tmp_path)
    manifest = read_manifest(version, CLASSES)

    train_only = train_only_sample_ids(manifest)
    group_b = {row.sample_id for row in manifest.rows if row.source_group == "B"}

    assert TRAIN_ONLY_SOURCE_GROUPS == frozenset({"B"})
    assert train_only == group_b
    assert train_only, "the fixture archive must hold a group B population"


def test_a_sample_photographed_in_two_groups_is_not_train_only(tmp_path):
    """Train-only is a property of the sample, not of a single photograph.

    A sample holding one group B photograph and one group A photograph carries
    evidence that is representative of deployment, so holding it out of the test
    set would discard a measurement rather than protect one.
    """
    source = write_archive(tmp_path)
    _image(61).save(source / "4 Clayey" / "119026_2 (2).JPEG", exif=_exif(), quality=95)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)

    manifest = read_manifest(version, CLASSES)
    assert "119026_2" not in train_only_sample_ids(manifest)
    assert "119026_1" in train_only_sample_ids(manifest)


# --- Acceptance criterion 12 -----------------------------------------------


def test_splits_read_declared_sample_ids_rather_than_the_filename(tmp_path):
    _, version, _ = ingest_into(tmp_path)
    manifest = read_manifest(version, CLASSES)

    declared = sample_ids_by_image(manifest)
    assert declared, "the manifest must map every image to a declared sample"
    for path, sample_id in declared.items():
        assert sample_id == Path(path).stem.split(" (")[0]


# --- Acceptance criterion 13 -----------------------------------------------


def test_admit_images_refuses_a_heic_file_by_name(tmp_path):
    _, version, _ = ingest_into(tmp_path)
    stray = version / "images" / "stray.heic"
    _image(77).save(stray, quality=90)

    result = subprocess.run(
        [sys.executable, "scripts/admit_images.py", "--root", str(version)],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "stray.heic" in combined
    assert "ingest_archive" in combined


# --- Acceptance criteria 9 and 14, against the real delivery ---------------

REAL_VERSION = Path(__file__).resolve().parents[1] / "data" / "datasets" / "v1"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file(),
    reason="the ingested version is not present; its images are not tracked",
)


@real_only
def test_ingested_version_reports_105_sample_groups_and_221_images():
    """The inventory, asserted so a later change in the archive is visible.

    105, not the 194 ADR 0016 recorded and not the 171 an earlier draft of
    SPEC 0040 carried. Both of those counted photographs the camera named as
    one sample each; 63 of them are 129 photographs taken in bursts.
    """
    manifest = read_manifest_or_none(REAL_VERSION, CLASSES)
    assert manifest is not None

    assert len(manifest.rows) == 221
    assert len({row.sample_id for row in manifest.rows}) == 105

    per_class = {}
    for row in manifest.rows:
        per_class.setdefault(row.texture_class, set()).add(row.sample_id)
    assert {name: len(ids) for name, ids in per_class.items()} == {
        "Arenosa": 26,
        "Media": 22,
        "Siltosa": 3,
        "Argilosa": 33,
        "Muito Argilosa": 21,
    }


@real_only
def test_the_real_version_records_how_every_sample_was_identified():
    manifest = read_manifest_or_none(REAL_VERSION, CLASSES)
    assert manifest is not None

    derived = derived_sample_ids(manifest)
    declared = {
        row.sample_id for row in manifest.rows if row.sample_id_source == "filename"
    }

    assert len(derived) == 63
    assert len(declared) == 42
    assert not (derived & declared), "a sample cannot be identified both ways"

    # Every derived identity comes from the HEIC session, which is the only
    # population the camera named.
    by_group = {
        row.source_group for row in manifest.rows if row.sample_id in derived
    }
    assert by_group == {"C"}


@real_only
def test_the_real_version_holds_group_b_only_in_argilosa_and_two_others():
    """The confound D6 exists for, asserted against the delivered data."""
    manifest = read_manifest_or_none(REAL_VERSION, CLASSES)
    assert manifest is not None

    restricted = train_only_sample_ids(manifest)
    per_class = {}
    for row in manifest.rows:
        if row.sample_id in restricted:
            per_class.setdefault(row.texture_class, set()).add(row.sample_id)

    assert {name: len(ids) for name, ids in per_class.items()} == {
        "Arenosa": 6,
        "Media": 2,
        "Argilosa": 17,
    }
    assert len(restricted) == 25


@real_only
def test_every_file_the_real_manifest_names_is_on_disk_and_decodable():
    manifest = read_manifest_or_none(REAL_VERSION, CLASSES)
    assert manifest is not None

    missing = [row.image for row in manifest.rows if not (REAL_VERSION / row.image).is_file()]
    if missing:
        pytest.skip(f"{len(missing)} image(s) absent; only the manifest is tracked")

    for row in manifest.rows:
        with Image.open(REAL_VERSION / row.image) as image:
            image.load()


@real_only
def test_the_real_manifest_holds_no_heic_row():
    manifest = read_manifest_or_none(REAL_VERSION, CLASSES)
    assert manifest is not None
    assert not [row for row in manifest.rows if row.image.lower().endswith(".heic")]


def test_read_manifest_or_none_returns_none_when_the_manifest_is_absent(tmp_path):
    assert read_manifest_or_none(tmp_path / "datasets" / "v1", CLASSES) is None


def test_read_manifest_or_none_still_raises_on_a_broken_manifest(tmp_path):
    root = tmp_path / "datasets" / "v1"
    root.mkdir(parents=True)
    (root / "manifest.csv").write_text("sample_id\nonly-one-column\n", encoding="utf-8")

    with pytest.raises((ManifestError, ValueError)):
        read_manifest_or_none(root, CLASSES)


# --- Acceptance criteria 10 and 11, through create_folds -------------------

#: Every class needs at least k splittable groups so that each of the k folds
#: holds one of it in its test side (SPEC 0042). Seven clears k = 5, and leaves
#: Argilosa above it once its three group B samples are held to training.
ELIGIBLE_PER_CLASS = 7

FOLD_COUNT = 5
REPEAT_COUNT = 3

SPLITTABLE_CLASSES = ("1 Sandy", "3 Medium", "4 Clayey", "5 Very Clayey")


def write_splittable_archive(tmp_path):
    """An archive large enough for a stratified three-way split.

    Every class holds seven photographs that carry EXIF, so they are group A and
    may be split. Argilosa additionally holds three that carry none, so they are
    group B and are restricted to training. JPEG throughout: what is under test
    is the split, and HEIC encoding would only make the fixture slower.
    """
    root = tmp_path / "archive"
    for folder in SPLITTABLE_CLASSES:
        (root / folder).mkdir(parents=True)

    seed = 0
    for folder in SPLITTABLE_CLASSES:
        for index in range(ELIGIBLE_PER_CLASS):
            seed += 1
            _image(seed).save(
                root / folder / f"{folder[0]}0{index},1 (1).JPEG",
                exif=_exif(),
                quality=95,
            )
    for index in range(3):
        seed += 1
        _image(seed).save(root / "4 Clayey" / f"119026_{index}.jpeg", quality=75)
    return root


def build_folds(tmp_path):
    from src.dataset import create_folds
    from src.manifest import class_images

    source = write_splittable_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)
    manifest = read_manifest(version, CLASSES)

    folds = create_folds(
        class_images(manifest, CLASSES),
        k=FOLD_COUNT,
        repeats=REPEAT_COUNT,
        seed=42,
        splits_dir=str(tmp_path / "splits"),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        train_only_samples=train_only_sample_ids(manifest),
    )
    return manifest, folds


def test_create_folds_places_no_group_b_sample_in_a_test_side(tmp_path):
    from src.dataset import fold_split

    manifest, folds = build_folds(tmp_path)

    restricted = train_only_sample_ids(manifest)
    assert len(restricted) == 3

    sample_of = sample_ids_by_image(manifest)
    for repeat in range(REPEAT_COUNT):
        for fold in range(FOLD_COUNT):
            split = fold_split(folds, repeat, fold)
            held = {sample_of[entry["path"]] for entry in split["test"]}
            assert not (held & restricted), (
                f"repeat {repeat} fold {fold} scores a train-only sample"
            )
            trained = {sample_of[entry["path"]] for entry in split["train"]}
            assert restricted <= trained, (
                "a restricted sample must still reach every training side"
            )


def test_create_folds_keeps_every_image_of_one_sample_on_one_side(tmp_path):
    from src.dataset import fold_split

    manifest, folds = build_folds(tmp_path)

    sample_of = sample_ids_by_image(manifest)
    for repeat in range(REPEAT_COUNT):
        for fold in range(FOLD_COUNT):
            split = fold_split(folds, repeat, fold)
            seen: dict[str, str] = {}
            for side, entries in split.items():
                for entry in entries:
                    sample_id = sample_of[entry["path"]]
                    assert seen.setdefault(sample_id, side) == side, (
                        f"sample {sample_id} reaches both {seen[sample_id]} "
                        f"and {side} in repeat {repeat} fold {fold}"
                    )


def test_create_folds_records_the_restricted_samples_in_the_manifest(tmp_path):
    import json

    _, _ = build_folds(tmp_path)
    written = json.loads((tmp_path / "splits" / "splits.json").read_text(encoding="utf-8"))

    assert written["train_only_samples"] == ["119026_0", "119026_1", "119026_2"]
    assert written["dataset_version"] == "v1"


def test_create_folds_refuses_when_every_group_is_restricted(tmp_path):
    from src.dataset import create_folds
    from src.manifest import class_images

    source = write_splittable_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)
    manifest = read_manifest(version, CLASSES)

    with pytest.raises(ValueError) as excinfo:
        create_folds(
            class_images(manifest, CLASSES),
            k=FOLD_COUNT,
            repeats=REPEAT_COUNT,
            seed=42,
            splits_dir=str(tmp_path / "splits"),
            sample_ids=sample_ids_by_image(manifest),
            train_only_samples={row.sample_id for row in manifest.rows},
        )

    assert "restricted to training" in str(excinfo.value)


# --- Sample identity for photographs the camera named ----------------------
#
# 129 of the 221 delivered photographs are called IMG_####. That name identifies
# the photograph and says nothing about the soil, so taking a sample id from it
# makes every shot its own sample — and two shots of one dish then land in two
# different splits, which is the leakage the grouping exists to prevent. The
# identity comes from the capture burst instead. Decided 2026-09-01.


def _camera_named(root, folder, number, when):
    """A camera-named photograph carrying a capture time and nothing else."""
    _image(number).save(
        root / folder / f"IMG_{number}.JPEG",
        exif=_exif(when=when),
        quality=95,
    )


def test_camera_named_photographs_in_one_burst_share_a_sample_id(tmp_path):
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    _camera_named(root, "1 Sandy", 8219, "2023:10:05 20:12:41")
    _camera_named(root, "1 Sandy", 8220, "2023:10:05 20:12:49")

    ids = {image.path.name: image.sample_id for image in scan_archive(root)}
    assert ids["IMG_8219.JPEG"] == ids["IMG_8220.JPEG"]
    assert ids["IMG_8219.JPEG"].startswith("burst-")


def test_a_gap_longer_than_the_threshold_starts_a_new_sample(tmp_path):
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    _camera_named(root, "1 Sandy", 8219, "2023:10:05 20:12:41")
    _camera_named(root, "1 Sandy", 8220, "2023:10:05 20:12:49")
    # 110 s after the second: the archive never shows a within-burst gap above
    # 23 s and never a between-burst gap below 100.
    _camera_named(root, "1 Sandy", 8221, "2023:10:05 20:14:39")

    ids = {image.path.name: image.sample_id for image in scan_archive(root)}
    assert ids["IMG_8219.JPEG"] == ids["IMG_8220.JPEG"]
    assert ids["IMG_8221.JPEG"] != ids["IMG_8219.JPEG"]
    assert len(set(ids.values())) == 2


def test_the_threshold_is_the_documented_one(tmp_path):
    """A gap of exactly the threshold still joins; one second more does not."""
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    _camera_named(root, "1 Sandy", 1000, "2023:10:05 10:00:00")
    _camera_named(root, "1 Sandy", 1001, f"2023:10:05 10:0{BURST_GAP_SECONDS // 60}:00")
    assert BURST_GAP_SECONDS == 60
    assert len({image.sample_id for image in scan_archive(root)}) == 1

    # 62 s after the second photograph, so the chain breaks. A burst is a
    # chain of gaps, not a window: three shots eight seconds apart are one
    # sample however long the burst runs.
    _camera_named(root, "1 Sandy", 1002, "2023:10:05 10:02:02")
    assert len({image.sample_id for image in scan_archive(root)}) == 2


def test_a_filename_that_declares_a_sample_is_never_regrouped_by_time(tmp_path):
    """Two lab-numbered photographs seconds apart stay two samples."""
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    for name in ("100262,1 (1)", "100999,7 (1)"):
        _image(hash(name) % 500).save(
            root / "1 Sandy" / f"{name}.JPEG",
            exif=_exif(when="2023:10:05 20:12:41"),
            quality=95,
        )

    images = scan_archive(root)
    assert {image.sample_id for image in images} == {"100262,1", "100999,7"}
    assert {image.sample_id_source for image in images} == {"filename"}


def test_a_camera_named_photograph_without_a_capture_time_is_refused(tmp_path):
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    _image(1).save(root / "1 Sandy" / "IMG_4242.JPEG", quality=95)

    with pytest.raises(ArchiveError) as excinfo:
        scan_archive(root)

    assert "IMG_4242.JPEG" in str(excinfo.value)
    assert "cannot be grouped" in str(excinfo.value)


def test_a_burst_spanning_two_classes_is_refused(tmp_path):
    """One sample has one class, so a burst that spans two is not one burst."""
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    (root / "4 Clayey").mkdir(parents=True)
    _camera_named(root, "1 Sandy", 9001, "2023:10:05 20:12:41")
    _camera_named(root, "4 Clayey", 9002, "2023:10:05 20:12:49")

    with pytest.raises(ArchiveError) as excinfo:
        scan_archive(root)

    assert "spans" in str(excinfo.value)
    assert "Arenosa" in str(excinfo.value)
    assert "Argilosa" in str(excinfo.value)


def test_manifest_records_how_each_sample_id_was_arrived_at(tmp_path):
    root = tmp_path / "archive"
    (root / "1 Sandy").mkdir(parents=True)
    (root / "3 Medium").mkdir(parents=True)
    (root / "4 Clayey").mkdir(parents=True)
    _camera_named(root, "1 Sandy", 8219, "2023:10:05 20:12:41")
    _camera_named(root, "1 Sandy", 8220, "2023:10:05 20:12:49")
    _image(5).save(
        root / "3 Medium" / "112098-3 (1).JPEG", exif=_exif(), quality=95
    )
    _image(6).save(root / "4 Clayey" / "119026_1.jpeg", quality=75)

    version = tmp_path / "datasets" / "v1"
    report = ingest_archive(root, version, classes=CLASSES)

    by_name = {
        Path(row["image"]).name: row["sample_id_source"] for row in rows_of(version)
    }
    assert by_name["IMG_8219.JPEG"] == "capture-burst"
    assert by_name["IMG_8220.JPEG"] == "capture-burst"
    assert by_name["112098-3 (1).JPEG"] == "filename"
    assert by_name["119026_1.jpeg"] == "filename"

    assert report.derived_samples == 1
    assert report.samples == 3

    manifest = read_manifest(version, CLASSES)
    assert len(derived_sample_ids(manifest)) == 1


def test_an_unaccepted_sample_id_source_is_refused(tmp_path):
    _, version, _ = ingest_into(tmp_path)
    path = version / "manifest.csv"
    text = path.read_text(encoding="utf-8").replace(",filename", ",invented", 1)
    path.write_text(text, encoding="utf-8")

    with pytest.raises(ManifestError) as excinfo:
        read_manifest(version, CLASSES)

    assert "sample_id_source" in str(excinfo.value)


# --- Resumable ingestion ---------------------------------------------------


def test_skip_existing_reuses_a_file_that_is_already_this_photograph(tmp_path):
    source = write_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    first = ingest_archive(source, version, classes=CLASSES)

    second = ingest_archive(source, version, classes=CLASSES, skip_existing=True)

    assert first.reused == 0
    assert second.reused == first.converted + first.copied
    assert second.converted == 0 and second.copied == 0


def test_skip_existing_rewrites_a_file_whose_bytes_do_not_match(tmp_path):
    source = write_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)

    row = next(row for row in rows_of(version) if row["source_format"] == "jpeg")
    target = version / row["image"]
    target.write_bytes(b"truncated")

    report = ingest_archive(source, version, classes=CLASSES, skip_existing=True)

    assert report.copied >= 1
    assert target.read_bytes() != b"truncated"


# --- Nothing in the archive is passed over in silence ----------------------


def test_a_file_at_the_archive_root_is_refused(tmp_path):
    """A photograph outside a class folder has no label, so it is not a skip."""
    source = write_archive(tmp_path)
    _image(80).save(source / "stray (1).JPEG", exif=_exif(), quality=95)

    with pytest.raises(ArchiveError) as excinfo:
        scan_archive(source)

    assert "stray (1).JPEG" in str(excinfo.value)
    assert "no class folder" in str(excinfo.value)


def test_a_nested_directory_inside_a_class_folder_is_refused(tmp_path):
    source = write_archive(tmp_path)
    nested = source / "1 Sandy" / "rescanned"
    nested.mkdir()
    _image(81).save(nested / "x (1).JPEG", exif=_exif(), quality=95)

    with pytest.raises(ArchiveError) as excinfo:
        scan_archive(source)

    assert "rescanned" in str(excinfo.value)
    assert "is a directory" in str(excinfo.value)


def test_skip_existing_rewrites_a_png_of_the_right_size_but_the_wrong_pixels(tmp_path):
    """A stale conversion is caught by its pixels, not by its dimensions.

    A dimension check alone would accept any valid PNG of the right shape and
    then record it as this photograph, which is how a partial or stale ingestion
    keeps wrong training data.
    """
    source = write_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    first = ingest_archive(source, version, classes=CLASSES)

    row = next(row for row in rows_of(version) if row["source_format"] == "heic")
    target = version / row["image"]
    original = Image.open(target).convert("RGB")
    Image.new("RGB", original.size, (7, 7, 7)).save(target, format="PNG")

    report = ingest_archive(source, version, classes=CLASSES, skip_existing=True)

    assert report.converted == 1
    assert report.reused == first.converted + first.copied - 1
    assert Image.open(target).convert("RGB").tobytes() == original.tobytes()


# --- A class cannot disappear between the manifest and the splits ----------


def test_create_folds_refuses_a_class_whose_every_group_is_restricted(tmp_path):
    """Restricting a whole class to training would silently drop it from scoring.

    The class keeps an output in the model and vanishes from every test side, so
    the reported metrics describe a different task from the one shipped.
    """
    from src.dataset import create_folds
    from src.manifest import class_images

    source = write_splittable_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)
    manifest = read_manifest(version, CLASSES)

    doomed = {
        row.sample_id for row in manifest.rows if row.texture_class == "Media"
    }

    with pytest.raises(ValueError) as excinfo:
        create_folds(
            class_images(manifest, CLASSES),
            k=FOLD_COUNT,
            repeats=REPEAT_COUNT,
            seed=42,
            splits_dir=str(tmp_path / "splits"),
            sample_ids=sample_ids_by_image(manifest),
            train_only_samples=doomed,
        )

    assert "Media" in str(excinfo.value)
    assert "splittable sample group" in str(excinfo.value)


def test_create_folds_for_config_refuses_a_configured_class_with_no_rows(tmp_path):
    """`class_images` omits an empty class, which reindexes every label after it."""
    from src.dataset import create_folds_for_config

    source = write_splittable_archive(tmp_path)
    version = tmp_path / "datasets" / "v1"
    ingest_archive(source, version, classes=CLASSES)

    cfg = {
        "classes": CLASSES,
        "data": {
            "datasets_dir": str(tmp_path / "datasets"),
            "dataset_version": "v1",
            "raw_dir": str(tmp_path / "raw"),
            "seed": 42,
        },
        "evaluation": {"k": FOLD_COUNT, "repeats": REPEAT_COUNT, "inner_k": 4},
    }

    with pytest.raises(ValueError) as excinfo:
        create_folds_for_config(cfg, str(tmp_path / "splits"))

    # The splittable fixture holds four of the five configured classes.
    assert "Siltosa" in str(excinfo.value)
