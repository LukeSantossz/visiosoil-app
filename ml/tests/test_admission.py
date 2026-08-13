"""Tests for dataset admission: the SPEC 0030 criteria gating what enters vN.

Every fixture image is synthesized from a seeded generator, so a verdict here is
a property of the criteria rather than of whatever image happened to be handy.
"""

import numpy as np
import pytest
from PIL import Image

from src.admission import admit, write_refusal_report
from src.image_quality import Verdict
from src.manifest import (
    METRIC_COLUMNS,
    QUALITY_FLAGS_COLUMN,
    REJECTED_FILENAME,
    REQUIRED_COLUMNS,
    QUALITY_VERDICT_COLUMN,
    read_manifest,
    write_manifest,
)

CLASSES = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]

#: Above the 512 px effective-resolution floor, so resolution never confounds a
#: fixture that is testing something else.
FIXTURE_SIDE_PX = 600


def noise_image(side, means, amplitude=40.0, seed=7):
    """A textured image with per-channel means, so blur and contrast both pass."""
    generator = np.random.default_rng(seed)
    noise = generator.uniform(-amplitude, amplitude, size=(side, side, 3))
    pixels = np.clip(noise + np.asarray(means, dtype=np.float64), 0.0, 255.0)
    return Image.fromarray(pixels.astype(np.uint8), mode="RGB")


def flat_image(side, level=128):
    """A featureless image: zero Laplacian variance, so blur blocks."""
    return Image.fromarray(
        np.full((side, side, 3), level, dtype=np.uint8), mode="RGB"
    )


def build_dataset(tmp_path, images):
    """Write a manifest plus its image files and return the version root.

    ``images`` maps a sample id to ``(setting, PIL image or raw bytes)`` pairs.
    """
    root = tmp_path / "datasets" / "v1"
    (root / "images").mkdir(parents=True)

    rows = []
    for sample_id, entries in images.items():
        for setting, content in entries:
            relative = f"images/{sample_id}_{setting}.png"
            target = root / relative
            if isinstance(content, bytes):
                target.write_bytes(content)
            else:
                content.save(target)
            rows.append(
                {
                    "sample_id": sample_id,
                    "texture_class": "Arenosa",
                    "image": relative,
                    "setting": setting,
                    "site": "Fazenda Um",
                    "device": "Pixel 8",
                    "captured_at": "2026-08-12",
                }
            )

    header = ",".join(REQUIRED_COLUMNS)
    lines = [header] + [
        ",".join(str(row[column]) for column in REQUIRED_COLUMNS) for row in rows
    ]
    (root / "manifest.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return root


@pytest.fixture
def ok_image():
    return noise_image(FIXTURE_SIDE_PX, (120, 120, 120))


@pytest.fixture
def advisory_image():
    """A strong red cast: colorCast fails, and colorCast cannot block."""
    return noise_image(FIXTURE_SIDE_PX, (170, 100, 100))


@pytest.fixture
def blocking_image():
    return flat_image(FIXTURE_SIDE_PX)


def test_admission_blocks_on_a_blocking_verdict(tmp_path, blocking_image):
    """A blocking image does not enter the dataset, and the reason is recorded."""
    root = build_dataset(tmp_path, {"S1": [("dish", blocking_image)]})

    result = admit(read_manifest(root, CLASSES))

    assert result.admitted == ()
    assert len(result.refused) == 1
    refusal = result.refused[0]
    assert refusal.image == "images/S1_dish.png"
    assert refusal.verdict == Verdict.BLOCKING.value
    assert "blur" in refusal.reason


def test_admission_admits_and_flags_an_advisory_verdict(tmp_path, advisory_image):
    """An advisory image enters with its failing criteria recorded."""
    root = build_dataset(tmp_path, {"S1": [("dish", advisory_image)]})

    result = admit(read_manifest(root, CLASSES))

    assert result.refused == ()
    admitted = result.admitted[0]
    assert admitted.quality_verdict == Verdict.ADVISORY.value
    assert "colorCast" in admitted.quality_flags


def test_admission_records_metrics_for_every_image(
    tmp_path, ok_image, advisory_image
):
    """Recalibration must be recomputable without re-reading a single file."""
    root = build_dataset(
        tmp_path, {"S1": [("dish", ok_image), ("paper", advisory_image)]}
    )

    result = admit(read_manifest(root, CLASSES))

    assert len(result.admitted) == 2
    for row in result.admitted:
        assert set(row.metrics) == set(METRIC_COLUMNS)


def test_admission_admits_an_ok_image_without_flags(tmp_path, ok_image):
    """A clean image carries no advisory flag."""
    root = build_dataset(tmp_path, {"S1": [("dish", ok_image)]})

    admitted = admit(read_manifest(root, CLASSES)).admitted[0]

    assert admitted.quality_verdict == Verdict.OK.value
    assert admitted.quality_flags == ()


def test_admission_refuses_an_unreadable_image_and_names_the_cause(tmp_path):
    """An image the analyzer cannot measure carries no metrics, so it cannot enter.

    SPEC 0030 requires an analyzer failure never to block a capture. Admission is
    the other context: a row with no recorded metrics would break the guarantee
    that a threshold change can be recomputed from the manifest, so the image is
    refused with its cause rather than admitted blind.
    """
    root = build_dataset(tmp_path, {"S1": [("dish", b"not an image")]})

    result = admit(read_manifest(root, CLASSES))

    assert result.admitted == ()
    assert result.refused[0].verdict == Verdict.UNVALIDATED.value
    assert result.refused[0].reason


def test_admission_writes_the_metrics_into_the_manifest(
    tmp_path, ok_image, advisory_image
):
    """The admitted manifest round-trips through the reader with its metrics."""
    root = build_dataset(
        tmp_path, {"S1": [("dish", ok_image), ("paper", advisory_image)]}
    )
    result = admit(read_manifest(root, CLASSES))

    write_manifest(root, result.admitted)

    reloaded = read_manifest(root, CLASSES, check_files=True)
    assert len(reloaded.rows) == 2
    for row in reloaded.rows:
        assert set(row.metrics) == set(METRIC_COLUMNS)
        assert row.quality_verdict in {Verdict.OK.value, Verdict.ADVISORY.value}
    assert any("colorCast" in row.quality_flags for row in reloaded.rows)


def test_write_refusal_report_names_every_refused_image(tmp_path, blocking_image):
    """A collector reads this file to know what to retake."""
    root = build_dataset(tmp_path, {"S1": [("dish", blocking_image)]})
    result = admit(read_manifest(root, CLASSES))

    report = write_refusal_report(root, result.refused)

    text = report.read_text(encoding="utf-8")
    assert report.name == REJECTED_FILENAME
    assert "images/S1_dish.png" in text
    assert "blur" in text


def test_write_refusal_report_writes_a_header_when_nothing_was_refused(
    tmp_path, ok_image
):
    """An empty report is still written, so its absence means it never ran."""
    root = build_dataset(tmp_path, {"S1": [("dish", ok_image)]})

    report = write_refusal_report(root, ())

    assert report.read_text(encoding="utf-8").strip() == "image,verdict,reason"


def test_write_manifest_preserves_the_schema_column_order(tmp_path, ok_image):
    """One writer owns the column order, so a manifest is never reshaped."""
    root = build_dataset(tmp_path, {"S1": [("dish", ok_image)]})
    result = admit(read_manifest(root, CLASSES))

    path = write_manifest(root, result.admitted)

    header = path.read_text(encoding="utf-8").splitlines()[0]
    expected = list(REQUIRED_COLUMNS) + [
        QUALITY_VERDICT_COLUMN,
        QUALITY_FLAGS_COLUMN,
        *METRIC_COLUMNS,
    ]
    assert header.split(",") == expected
