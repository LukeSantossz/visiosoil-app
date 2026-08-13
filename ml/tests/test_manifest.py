"""Tests for the dataset manifest: schema, values, disk agreement, and grouping.

Every case builds a synthetic manifest and generated files in a temporary
directory, so the suite runs before any real dataset exists. That is a
requirement of SPEC 0033 rather than a convenience: the protocol has to be
finishable and checkable before a single photograph is taken.
"""

import pytest

from src.manifest import (
    FLAG_SEPARATOR,
    MANIFEST_FILENAME,
    METRIC_COLUMNS,
    QUALITY_FLAGS_COLUMN,
    QUALITY_VERDICT_COLUMN,
    QUARANTINE_DIRNAME,
    REQUIRED_COLUMNS,
    VALID_SETTINGS,
    ManifestError,
    check_class_coverage,
    check_setting_pairing,
    class_images,
    dataset_root,
    format_composition,
    manifest_digest,
    read_manifest,
    sample_ids_by_image,
    split_composition,
    verify_directory,
    verify_split_digest,
)

CLASSES = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]

# A 1x1 JPEG header is enough wherever a test only needs the file to exist.
# Admission is the only caller that decodes, and it has its own fixtures.
PLACEHOLDER_IMAGE_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 64


def paired_rows(sample_id, texture_class, *, site="Fazenda Um", device="Pixel 8"):
    """The two rows the protocol requires per physical sample."""
    return [
        {
            "sample_id": sample_id,
            "texture_class": texture_class,
            "image": f"images/{sample_id}_{setting}.jpg",
            "setting": setting,
            "site": site,
            "device": device,
            "captured_at": "2026-08-12",
        }
        for setting in VALID_SETTINGS
    ]


def write_dataset(
    tmp_path,
    rows,
    *,
    columns=None,
    delimiter=",",
    encoding="utf-8",
    version="v1",
    create_images=True,
):
    """Write a manifest (and optionally its images) and return the version root."""
    root = tmp_path / "datasets" / version
    root.mkdir(parents=True, exist_ok=True)

    header = list(columns) if columns is not None else list(REQUIRED_COLUMNS)
    lines = [delimiter.join(header)]
    for row in rows:
        lines.append(delimiter.join(str(row.get(column, "")) for column in header))
    text = "\n".join(lines) + "\n"
    (root / MANIFEST_FILENAME).write_bytes(text.encode(encoding))

    if create_images:
        for row in rows:
            image = row.get("image")
            if not image:
                continue
            target = root / image
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(PLACEHOLDER_IMAGE_BYTES)

    return root


@pytest.fixture
def valid_root(tmp_path):
    """Three paired samples per class: enough groups for a stratified split."""
    rows = []
    for texture_class in CLASSES:
        prefix = texture_class.replace(" ", "_")
        for index in range(3):
            rows.extend(paired_rows(f"{prefix}-{index}", texture_class))
    return write_dataset(tmp_path, rows)


def test_manifest_requires_every_column(tmp_path):
    """A manifest missing required columns is rejected, naming the missing ones."""
    columns = [c for c in REQUIRED_COLUMNS if c not in {"site", "device"}]
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"), columns=columns)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "not present" in message
    assert "site" in message
    assert "device" in message


def test_manifest_rejects_a_duplicate_sample_id_across_classes(tmp_path):
    """One identifier under two classes is a labelling error, not a collision."""
    rows = paired_rows("S1", "Arenosa") + paired_rows("S1", "Argilosa")
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "S1" in message
    assert "Arenosa" in message
    assert "Argilosa" in message


def test_manifest_accepts_repeated_sample_id_within_one_class(tmp_path):
    """Several photographs of one sample share an identifier and form one group."""
    rows = paired_rows("S1", "Arenosa")
    rows.append(
        {
            "sample_id": "S1",
            "texture_class": "Arenosa",
            "image": "images/S1_dish_2.jpg",
            "setting": "dish",
            "site": "Fazenda Um",
            "device": "Pixel 8",
            "captured_at": "2026-08-12",
        }
    )
    root = write_dataset(tmp_path, rows)

    manifest = read_manifest(root, CLASSES)

    assert len(manifest.rows) == 3
    assert set(sample_ids_by_image(manifest).values()) == {"S1"}


def test_manifest_requires_exactly_one_photograph_per_setting_per_sample(tmp_path):
    """A sample missing a condition, or doubling one, is reported by name."""
    rows = [paired_rows("Paired", "Arenosa")[0]]  # dish only
    rows[0]["sample_id"] = "DishOnly"
    rows[0]["image"] = "images/DishOnly_dish.jpg"
    rows.extend(paired_rows("Doubled", "Media"))
    rows.append(
        {
            "sample_id": "Doubled",
            "texture_class": "Media",
            "image": "images/Doubled_dish_2.jpg",
            "setting": "dish",
            "site": "Fazenda Um",
            "device": "Pixel 8",
            "captured_at": "2026-08-12",
        }
    )
    root = write_dataset(tmp_path, rows)
    manifest = read_manifest(root, CLASSES)

    problems = check_setting_pairing(manifest)

    joined = "\n".join(problems)
    assert "DishOnly" in joined
    assert "paper" in joined
    assert "Doubled" in joined


def test_manifest_pairing_accepts_one_photograph_per_setting(tmp_path):
    """The paired case produces no pairing problem."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))

    assert check_setting_pairing(read_manifest(root, CLASSES)) == []


def test_manifest_rejects_an_unknown_class(tmp_path):
    """A class outside config.yaml is rejected, naming it and the accepted set."""
    root = write_dataset(tmp_path, paired_rows("S1", "Barro"))

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "Barro" in message
    assert "Arenosa" in message


def test_manifest_rejects_an_unknown_setting_value(tmp_path):
    """Anything outside dish and paper is rejected, including in_situ."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["setting"] = "in_situ"
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "in_situ" in message
    assert "dish" in message
    assert "paper" in message


def test_manifest_rejects_a_granulometry_column(tmp_path):
    """No granulometric data enters the process, so the column is rejected."""
    columns = list(REQUIRED_COLUMNS) + ["clay_pct"]
    rows = paired_rows("S1", "Arenosa")
    for row in rows:
        row["clay_pct"] = "42"
    root = write_dataset(tmp_path, rows, columns=columns)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "clay_pct" in str(error.value)


def test_manifest_rejects_a_lab_report_column(tmp_path):
    """The laboratory reference is absent for the same reason as the percentages."""
    columns = list(REQUIRED_COLUMNS) + ["lab_report"]
    rows = paired_rows("S1", "Arenosa")
    for row in rows:
        row["lab_report"] = "LR-1"
    root = write_dataset(tmp_path, rows, columns=columns)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "lab_report" in str(error.value)


def test_manifest_reports_every_problem_at_once(tmp_path):
    """Four distinct problems produce one failure naming all four."""
    rows = paired_rows("Shared", "Arenosa") + paired_rows("Shared", "Argilosa")
    rows[0]["texture_class"] = "Barro"
    rows[2]["setting"] = "in_situ"
    rows.extend(paired_rows("Missing", "Media"))
    root = write_dataset(tmp_path, rows)
    (root / rows[-1]["image"]).unlink()

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES, check_files=True)

    message = str(error.value)
    assert "Barro" in message
    assert "in_situ" in message
    assert "Shared" in message
    assert "Missing_paper.jpg" in message


def test_semicolon_delimited_manifest_is_diagnosed(tmp_path):
    """A pt-BR spreadsheet export fails naming the delimiter, not a column."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"), delimiter=";")

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "semicolon" in message.lower()
    # The wrong diagnosis sends a collector looking for a column that is right
    # there, so the absent-column wording must not appear.
    assert "not present" not in message


def test_non_utf8_manifest_is_diagnosed(tmp_path):
    """A Latin-1 export fails with a message naming the encoding."""
    rows = paired_rows("S1", "Arenosa", site="Fazenda São João")
    root = write_dataset(tmp_path, rows, encoding="latin-1")

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "UTF-8" in str(error.value)


def test_directory_and_manifest_must_agree(tmp_path):
    """An orphan file and a missing file are each reported, naming the path."""
    rows = paired_rows("S1", "Arenosa")
    root = write_dataset(tmp_path, rows)
    (root / rows[1]["image"]).unlink()
    (root / "images" / "orphan.jpg").write_bytes(PLACEHOLDER_IMAGE_BYTES)

    problems = verify_directory(read_manifest(root, CLASSES))

    joined = "\n".join(problems)
    assert "S1_paper.jpg" in joined
    assert "orphan.jpg" in joined


def test_verify_directory_ignores_the_manifest_and_the_rejection_report(tmp_path):
    """Bookkeeping files next to the images are not orphan images."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))
    (root / "admission-rejected.csv").write_text("image\n", encoding="utf-8")

    assert verify_directory(read_manifest(root, CLASSES)) == []


def test_manifest_digest_changes_with_content(tmp_path):
    """The digest is over the file bytes, so any edit moves it."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))
    before = manifest_digest(root)

    (root / MANIFEST_FILENAME).write_bytes(
        (root / MANIFEST_FILENAME).read_bytes() + b"\n"
    )

    assert manifest_digest(root) != before


def test_verify_split_digest_rejects_a_stale_split(tmp_path):
    """A split that does not belong to the current manifest fails loudly."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))
    split_manifest = {"dataset_version": "v1", "manifest_digest": "stale"}

    with pytest.raises(ValueError) as error:
        verify_split_digest(split_manifest, manifest_digest(root))

    assert "stale" in str(error.value)


def test_verify_split_digest_accepts_a_matching_split(tmp_path):
    """The matching case passes without raising."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))
    digest = manifest_digest(root)

    verify_split_digest({"dataset_version": "v1", "manifest_digest": digest}, digest)


def test_verify_split_digest_rejects_a_split_without_a_digest():
    """A split predating this schema cannot be shown to match anything."""
    with pytest.raises(ValueError) as error:
        verify_split_digest({"dataset_version": "v1"}, "abc")

    assert "manifest_digest" in str(error.value)


def test_class_images_follows_config_class_order(valid_root):
    """Class order comes from config, never from the manifest or sorted()."""
    manifest = read_manifest(valid_root, CLASSES)

    assert list(class_images(manifest, CLASSES).keys()) == CLASSES


def test_class_images_resolves_paths_against_the_version_root(tmp_path):
    """Manifest paths are relative; consumers get resolved absolute paths."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))

    paths = class_images(read_manifest(root, CLASSES), CLASSES)["Arenosa"]

    assert paths == sorted(str(root / f"images/S1_{s}.jpg") for s in VALID_SETTINGS)


def test_split_composition_counts_class_site_and_device(tmp_path):
    """The report covers all three axes the protocol records."""
    rows = paired_rows("S1", "Arenosa", site="Fazenda Um", device="Pixel 8")
    rows += paired_rows("S2", "Media", site="Fazenda Dois", device="Pixel 8")
    root = write_dataset(tmp_path, rows)
    manifest = read_manifest(root, CLASSES)
    splits = {
        "train": [{"path": str(root / rows[0]["image"]), "class": "Arenosa"}],
        "test": [{"path": str(root / rows[2]["image"]), "class": "Media"}],
    }

    composition = split_composition(splits, manifest)

    assert composition["train"]["class"]["Arenosa"] == 1
    assert composition["train"]["site"]["Fazenda Um"] == 1
    assert composition["train"]["device"]["Pixel 8"] == 1
    assert composition["test"]["site"]["Fazenda Dois"] == 1


def test_format_composition_names_every_axis(tmp_path):
    """What the validator prints has to be readable, so it is asserted."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))
    manifest = read_manifest(root, CLASSES)
    splits = {"train": [{"path": str(root / "images/S1_dish.jpg"), "class": "Arenosa"}]}

    text = format_composition(split_composition(splits, manifest))

    assert "train" in text
    assert "Arenosa" in text
    assert "site" in text
    assert "device" in text


def test_admission_columns_round_trip(tmp_path):
    """Metrics and flags written by admission are read back as values."""
    columns = list(REQUIRED_COLUMNS) + [
        QUALITY_VERDICT_COLUMN,
        QUALITY_FLAGS_COLUMN,
        *METRIC_COLUMNS,
    ]
    rows = paired_rows("S1", "Arenosa")
    for row in rows:
        row[QUALITY_VERDICT_COLUMN] = "advisory"
        row[QUALITY_FLAGS_COLUMN] = FLAG_SEPARATOR.join(["contrast", "specular"])
        for index, metric in enumerate(METRIC_COLUMNS):
            row[metric] = float(index)
    root = write_dataset(tmp_path, rows, columns=columns)

    first = read_manifest(root, CLASSES).rows[0]

    assert first.quality_verdict == "advisory"
    assert first.quality_flags == ("contrast", "specular")
    assert first.metrics["blur_score"] == 0.0
    assert len(first.metrics) == len(METRIC_COLUMNS)


def test_dataset_root_joins_the_version_directory(tmp_path):
    """A version is a directory name, and only one function builds the path."""
    assert dataset_root(tmp_path / "datasets", "v3") == tmp_path / "datasets" / "v3"


@pytest.mark.parametrize("version", ["../other", "..\\other", "/etc", "C:\\data", "latest", "v0", ""])
def test_dataset_root_rejects_a_version_that_is_not_a_version_name(tmp_path, version):
    """A version reaches this from a command-line flag, not only from the config.

    `config.yaml` validates its own value, so the flag was the unvalidated way in:
    joined straight onto the datasets root, `../other` makes a writing command
    operate outside `data/datasets` entirely.
    """
    with pytest.raises(ValueError, match="dataset version"):
        dataset_root(tmp_path / "datasets", version)


@pytest.mark.parametrize("captured_at", ["20260812", "2026-W33-3", "2026-224"])
def test_read_manifest_rejects_a_non_canonical_iso_date(tmp_path, captured_at):
    """`date.fromisoformat` accepts forms the protocol and the message do not.

    Both say `YYYY-MM-DD`; accepting a compact or week-date form means metadata
    that no two readers sort or group the same way.
    """
    rows = paired_rows("S1", "Arenosa")
    rows[0]["captured_at"] = captured_at
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "captured_at" in str(error.value)


def test_read_manifest_accepts_a_canonical_iso_date(tmp_path):
    """The documented form still passes."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))

    assert read_manifest(root, CLASSES).rows[0].captured_at == "2026-08-12"


def test_read_manifest_rejects_an_empty_manifest(tmp_path):
    """An empty dataset is a mistake, and a silent empty split is worse."""
    root = write_dataset(tmp_path, [])

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "no rows" in str(error.value).lower()


def test_read_manifest_rejects_a_missing_file(tmp_path):
    """A missing manifest names the path it looked for."""
    root = tmp_path / "datasets" / "v1"
    root.mkdir(parents=True)

    with pytest.raises(FileNotFoundError) as error:
        read_manifest(root, CLASSES)

    assert MANIFEST_FILENAME in str(error.value)


def test_read_manifest_rejects_a_blank_required_value(tmp_path):
    """A blank cell in a required column is not a value."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["site"] = ""
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "site" in message
    assert "row 2" in message


def test_read_manifest_rejects_a_duplicate_image_path(tmp_path):
    """Two rows claiming one file would double-count it in a split."""
    rows = paired_rows("S1", "Arenosa")
    rows[1]["image"] = rows[0]["image"]
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "S1_dish.jpg" in str(error.value)


def test_read_manifest_rejects_an_absolute_image_path(tmp_path):
    """Paths are relative to the version root so a dataset stays movable."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["image"] = "/tmp/absolute.jpg"
    root = write_dataset(tmp_path, rows, create_images=False)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES, check_files=False)

    assert "relative" in str(error.value).lower()


def test_read_manifest_rejects_an_escaping_image_path(tmp_path):
    """A row must not reach outside the dataset version it belongs to."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["image"] = "../v2/images/leak.jpg"
    root = write_dataset(tmp_path, rows, create_images=False)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES, check_files=False)

    assert "outside" in str(error.value).lower()


def test_read_manifest_rejects_a_non_iso_capture_date(tmp_path):
    """captured_at is an ISO 8601 date, and a free-text date is not sortable."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["captured_at"] = "12/08/2026"
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    message = str(error.value)
    assert "captured_at" in message
    assert "12/08/2026" in message


def test_read_manifest_records_the_version_and_digest(tmp_path):
    """A manifest knows which version it is and what it hashes to."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"), version="v7")

    manifest = read_manifest(root, CLASSES)

    assert manifest.version == "v7"
    assert manifest.digest == manifest_digest(root)


def test_read_manifest_rejects_two_rows_aliasing_one_file(tmp_path):
    """A different spelling of one path is still one file.

    Comparing the raw strings lets `./images/x.jpg` and `images/x.jpg` both
    through, after which the second row silently takes over the first row's
    group and one photograph is counted under the wrong sample.
    """
    rows = paired_rows("S1", "Arenosa") + paired_rows("S2", "Media")
    rows[2]["image"] = "./" + rows[0]["image"]
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert "already claimed" in str(error.value)


def test_read_manifest_rejects_a_drive_relative_image_path(tmp_path):
    """`C:images/a.jpg` names different files on Windows and on POSIX."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["image"] = "C:images/a.jpg"
    root = write_dataset(tmp_path, rows, create_images=False)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES, check_files=False)

    assert "drive" in str(error.value).lower()


def test_check_class_coverage_reports_a_class_with_no_rows(tmp_path):
    """A five-way product cannot be trained from a four-class dataset.

    The class list is the model's output order, so a class at zero silently
    reindexes every label rather than merely thinning the data.
    """
    rows = []
    for texture_class in CLASSES:
        if texture_class == "Siltosa":
            continue
        rows.extend(paired_rows(texture_class.replace(" ", "_"), texture_class))
    root = write_dataset(tmp_path, rows)

    problems = check_class_coverage(read_manifest(root, CLASSES), CLASSES)

    joined = "\n".join(problems)
    assert "Siltosa" in joined
    assert "Arenosa" not in joined


def test_check_class_coverage_passes_when_every_class_has_rows(tmp_path):
    """The complete case reports nothing."""
    rows = []
    for texture_class in CLASSES:
        rows.extend(paired_rows(texture_class.replace(" ", "_"), texture_class))
    root = write_dataset(tmp_path, rows)

    assert check_class_coverage(read_manifest(root, CLASSES), CLASSES) == []


def test_verify_directory_ignores_the_quarantine_directory(tmp_path):
    """A refused image kept as evidence is not an orphan of the dataset."""
    root = write_dataset(tmp_path, paired_rows("S1", "Arenosa"))
    quarantine = root / QUARANTINE_DIRNAME
    quarantine.mkdir()
    (quarantine / "refused.jpg").write_bytes(PLACEHOLDER_IMAGE_BYTES)

    assert verify_directory(read_manifest(root, CLASSES)) == []


def test_read_manifest_rejects_a_row_inside_the_quarantine_directory(tmp_path):
    """Quarantine holds what was refused, so nothing may be declared from it."""
    rows = paired_rows("S1", "Arenosa")
    rows[0]["image"] = f"{QUARANTINE_DIRNAME}/S1_dish.jpg"
    root = write_dataset(tmp_path, rows)

    with pytest.raises(ManifestError) as error:
        read_manifest(root, CLASSES)

    assert QUARANTINE_DIRNAME in str(error.value)
