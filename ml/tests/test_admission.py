"""Tests for dataset admission: the SPEC 0030 criteria gating what enters vN.

Every fixture image is synthesized from a seeded generator, so a verdict here is
a property of the criteria rather than of whatever image happened to be handy.
"""

from pathlib import Path

import pytest

from src.admission import admit, quarantine_refused, write_refusal_report
from src.image_quality import Verdict
from src.manifest import (
    METRIC_COLUMNS,
    QUARANTINE_DIRNAME,
    QUALITY_FLAGS_COLUMN,
    QUALITY_VERDICT_COLUMN,
    REJECTED_FILENAME,
    REQUIRED_COLUMNS,
    read_manifest,
    write_manifest,
)
from tests.support import CLASSES, flat_image, noise_image, write_image_version


@pytest.fixture
def ok_image():
    return noise_image()


@pytest.fixture
def advisory_image():
    """A strong red cast: colorCast fails, and colorCast cannot block."""
    return noise_image(means=(170, 100, 100))


@pytest.fixture
def blocking_image():
    return flat_image()


def test_admission_blocks_on_a_blocking_verdict(tmp_path, blocking_image):
    """A blocking image does not enter the dataset, and the reason is recorded."""
    root = write_image_version(tmp_path, {"S1": [("dish", blocking_image)]})

    result = admit(read_manifest(root, CLASSES))

    assert result.admitted == ()
    assert len(result.refused) == 1
    refusal = result.refused[0]
    assert refusal.image == "images/S1_dish.png"
    assert refusal.verdict == Verdict.BLOCKING.value
    assert "blur" in refusal.reason


def test_admission_admits_and_flags_an_advisory_verdict(tmp_path, advisory_image):
    """An advisory image enters with its failing criteria recorded."""
    root = write_image_version(tmp_path, {"S1": [("dish", advisory_image)]})

    result = admit(read_manifest(root, CLASSES))

    assert result.refused == ()
    admitted = result.admitted[0]
    assert admitted.quality_verdict == Verdict.ADVISORY.value
    assert "colorCast" in admitted.quality_flags


def test_admission_records_metrics_for_every_image(
    tmp_path, ok_image, advisory_image
):
    """Recalibration must be recomputable without re-reading a single file."""
    root = write_image_version(
        tmp_path, {"S1": [("dish", ok_image), ("paper", advisory_image)]}
    )

    result = admit(read_manifest(root, CLASSES))

    assert len(result.admitted) == 2
    for row in result.admitted:
        assert set(row.metrics) == set(METRIC_COLUMNS)


def test_admission_admits_an_ok_image_without_flags(tmp_path, ok_image):
    """A clean image carries no advisory flag."""
    root = write_image_version(tmp_path, {"S1": [("dish", ok_image)]})

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
    root = write_image_version(tmp_path, {"S1": [("dish", b"not an image")]})

    result = admit(read_manifest(root, CLASSES))

    assert result.admitted == ()
    assert result.refused[0].verdict == Verdict.UNVALIDATED.value
    assert result.refused[0].reason


def test_admission_writes_the_metrics_into_the_manifest(
    tmp_path, ok_image, advisory_image
):
    """The admitted manifest round-trips through the reader with its metrics."""
    root = write_image_version(
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
    root = write_image_version(tmp_path, {"S1": [("dish", blocking_image)]})
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
    root = write_image_version(tmp_path, {"S1": [("dish", ok_image)]})

    report = write_refusal_report(root, ())

    assert report.read_text(encoding="utf-8").strip() == "image,verdict,reason"


def test_quarantine_moves_nothing_when_a_source_is_absent(tmp_path, blocking_image):
    """A partial move would leave the dataset in the state quarantine prevents.

    The caller rewrites the manifest around this call, so a failure halfway
    through would drop rows whose files had not moved — exactly the orphan state
    quarantine exists to avoid. Everything is checked before anything moves.
    """
    root = write_image_version(
        tmp_path,
        {"S1": [("dish", blocking_image)], "S2": [("dish", flat_image())]},
    )
    refused = admit(read_manifest(root, CLASSES)).refused
    assert len(refused) == 2
    (root / refused[1].image).unlink()

    with pytest.raises(FileNotFoundError):
        quarantine_refused(root, refused)

    assert (root / refused[0].image).is_file()
    assert not (root / QUARANTINE_DIRNAME).exists()


def test_quarantine_rolls_back_a_move_that_failed_partway(
    tmp_path, blocking_image, monkeypatch
):
    """A move that fails on the second file must undo the first.

    The pre-flight covers a missing source and an occupied target, but not a
    permission error or a cross-device rename raised by the move itself. Without
    a rollback the first file sits in quarantine while the manifest — which the
    caller then leaves uncommitted — still declares it, which is the orphan state
    the whole mechanism exists to avoid.
    """
    root = write_image_version(
        tmp_path,
        {
            "S1": [("dish", blocking_image)],
            "S2": [("dish", flat_image())],
            "S3": [("dish", flat_image())],
        },
    )
    refused = admit(read_manifest(root, CLASSES)).refused
    assert len(refused) == 3

    real_replace = Path.replace
    calls = {"n": 0}

    def failing_replace(self, target):
        calls["n"] += 1
        if calls["n"] == 2:
            raise PermissionError("target locked")
        return real_replace(self, target)

    monkeypatch.setattr(Path, "replace", failing_replace)

    with pytest.raises(PermissionError):
        quarantine_refused(root, refused)

    monkeypatch.undo()
    for refusal in refused:
        assert (root / refusal.image).is_file(), f"{refusal.image} was not restored"
    assert not any((root / QUARANTINE_DIRNAME).rglob("*.png"))


def test_quarantine_refuses_to_overwrite_existing_evidence(tmp_path, blocking_image):
    """The record of an earlier refusal is not scratch space for a later one."""
    root = write_image_version(tmp_path, {"S1": [("dish", blocking_image)]})
    refused = admit(read_manifest(root, CLASSES)).refused
    quarantine_refused(root, refused)
    blocking_image.save(root / refused[0].image)

    with pytest.raises(FileExistsError) as error:
        quarantine_refused(root, refused)

    assert refused[0].image in str(error.value)


def test_write_manifest_preserves_the_schema_column_order(tmp_path, ok_image):
    """One writer owns the column order, so a manifest is never reshaped."""
    root = write_image_version(tmp_path, {"S1": [("dish", ok_image)]})
    result = admit(read_manifest(root, CLASSES))

    path = write_manifest(root, result.admitted)

    header = path.read_text(encoding="utf-8").splitlines()[0]
    expected = list(REQUIRED_COLUMNS) + [
        QUALITY_VERDICT_COLUMN,
        QUALITY_FLAGS_COLUMN,
        *METRIC_COLUMNS,
    ]
    assert header.split(",") == expected
