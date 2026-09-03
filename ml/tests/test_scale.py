"""Acceptance criteria for the dish-rim scale reader (SPEC 0052).

Each test name matches an acceptance criterion in
`docs/specs/0052-read-the-dish-rim-and-recompute-the-canonical-scale.md`.

The fixtures are rendered circles, so most of the suite runs without the
archive. The dataset-gated tests at the end assert the committed measurement
record against the version it was taken over; SPEC 0043 requires that no
criterion be covered only by those, and none is.
"""

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from src.manifest import (
    ARCHIVE_CLASSES,
    read_manifest,
    train_only_sample_ids,
    unmeasured_digest,
)
from src.scale import (
    DISH_DIAMETER_MM,
    ScaleRefusal,
    canonical_mm_per_px,
    read_dish_scale,
    summarise,
)
from tests.support import CLASSES, write_image_version

ML_ROOT = Path(__file__).resolve().parents[1]
RECORD_PATH = ML_ROOT / "measurements" / "dish-scale-v1.json"
REAL_VERSION = ML_ROOT / "data" / "datasets" / "v1"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file(),
    reason="the ingested version is not present; its images are not tracked",
)


def _load_script(name: str):
    """Import a file under `scripts/` that is not part of a package."""
    path = ML_ROOT / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# --- fixture builders: deterministic, no randomness ------------------------


def _dish(
    side: int = 900,
    outer_radius: float = 300.0,
    inner_radius: float | None = None,
    centre: tuple[float, float] | None = None,
    background: int = 235,
    glass: int = 210,
    wall: int = 130,
    soil: int = 70,
) -> Image.Image:
    """Render the cross-section a glass dish actually presents.

    Outward from the middle: soil, the bright glass floor of the rim, the dark
    line of the wall itself, then the bench. The wall line matters — a dish
    rendered as one weak step from glass to bench is not what the archive holds,
    and a fixture that models the boundary as weaker than it is would be testing
    an image this reader will never see.

    `inner_radius` defaults to a full dish, where the soil meets the wall. A
    smaller value renders the under-filled dish that made the soil disc
    unusable as a reference.
    """
    if inner_radius is None:
        inner_radius = outer_radius * 0.94
    cy, cx = centre if centre is not None else (side / 2.0, side / 2.0)
    ys, xs = np.mgrid[0:side, 0:side]
    radius = np.hypot(ys - cy, xs - cx)
    plane = np.full((side, side), background, dtype=np.float64)
    plane[radius <= outer_radius] = wall
    plane[radius <= outer_radius * 0.98] = glass
    plane[radius <= inner_radius] = soil
    return Image.fromarray(
        np.dstack([plane, plane, plane]).astype(np.uint8), mode="RGB"
    )


def _blank(side: int = 900, value: int = 235) -> Image.Image:
    plane = np.full((side, side, 3), value, dtype=np.uint8)
    return Image.fromarray(plane, mode="RGB")


def _tilted_dish(
    side: int = 900, radius: float = 300.0, aspect: float = 1.25
) -> Image.Image:
    """The same dish photographed off the perpendicular, so the rim is elliptic.

    This is the realistic way a rim stops being a circle, and it is the case the
    dispersion refusal exists for: a strong, clean boundary that is nonetheless
    not the shape whose diameter is known to be 90 mm.
    """
    cy = cx = side / 2.0
    ys, xs = np.mgrid[0:side, 0:side]
    inside = np.hypot((ys - cy) / aspect, xs - cx) <= radius
    edge = np.hypot((ys - cy) / aspect, xs - cx) <= radius * 0.98
    plane = np.full((side, side), 235, dtype=np.float64)
    plane[inside] = 130
    plane[edge] = 70
    return Image.fromarray(
        np.dstack([plane, plane, plane]).astype(np.uint8), mode="RGB"
    )


# --- the reader ------------------------------------------------------------


@pytest.mark.parametrize(
    "side,outer_radius",
    [(900, 300.0), (800, 250.0), (700, 230.0), (640, 168.0), (640, 224.0), (1200, 400.0)],
)
def test_reads_the_rim_of_a_synthetic_dish_within_one_percent(side, outer_radius):
    """Across frame sizes, because one geometry proves only that one geometry.

    The single case this test used to carry passed while the reader was five
    per cent wrong at four of the five sizes added here.
    """
    reading = read_dish_scale(_dish(side=side, outer_radius=outer_radius))

    assert reading.refusal is None
    assert reading.disc_diameter_px == pytest.approx(2.0 * outer_radius, rel=0.01)
    assert reading.mm_per_px == pytest.approx(
        DISH_DIAMETER_MM / (2.0 * outer_radius), rel=0.01
    )


@pytest.mark.parametrize("inner_radius", [285.0, 282.0, 270.0, 250.0, 220.0])
def test_measures_the_outer_circle_not_the_inner_one(inner_radius):
    """The soil disc is the strongest edge; the rim is the reference.

    Parametrised over how full the dish is, and the full end is the case that
    matters. This test used to pin the soil at 0.73 of the rim, far outside the
    band the per-ray refinement searches, so it could not see the reader
    snapping to the soil boundary on a dish filled the way every archive
    photograph is — a clean circle five per cent too small, reported with no
    refusal and a dispersion of 0.0005.
    """
    reading = read_dish_scale(_dish(outer_radius=300.0, inner_radius=inner_radius))

    assert reading.refusal is None
    assert reading.disc_diameter_px == pytest.approx(600.0, rel=0.01)


def test_refuses_when_no_circle_is_present():
    reading = read_dish_scale(_blank())

    assert reading.refusal is ScaleRefusal.NO_CIRCLE_FOUND


def test_refuses_when_the_rim_is_inconsistent():
    reading = read_dish_scale(_tilted_dish(aspect=1.25))

    assert reading.refusal is ScaleRefusal.INCONSISTENT_RIM


def test_never_substitutes_a_default_scale():
    """Every refusal carries no number at all, on every cause."""
    refused = [read_dish_scale(_blank()), read_dish_scale(_tilted_dish(aspect=1.25))]

    assert {reading.refusal for reading in refused} == set(ScaleRefusal)
    for reading in refused:
        assert reading.mm_per_px is None
        assert reading.disc_diameter_px is None


def test_a_refusal_from_the_diagnostic_pass_reports_no_metrics():
    """Its numbers come from another fit, and they routinely look like a pass.

    The diagnostic pass re-fits at a different quantile, often at the centre the
    vote proposed rather than the one the fit corrected. Attaching its
    dispersion and coverage to the refusal produced a record saying the rim was
    inconsistent beside a dispersion of 0.0023 against a limit of 0.06.
    """
    reading = read_dish_scale(_tilted_dish(aspect=1.25))

    assert reading.refusal is ScaleRefusal.INCONSISTENT_RIM
    assert reading.rim_dispersion == 0.0
    assert reading.ray_coverage == 0.0


def test_reports_dispersion_and_ray_coverage_with_every_reading():
    reading = read_dish_scale(_dish())

    assert reading.refusal is None
    assert 0.0 <= reading.rim_dispersion < 0.05
    assert 0.5 < reading.ray_coverage <= 1.0


def test_is_deterministic_across_runs():
    image = _dish(outer_radius=271.0, centre=(410.0, 480.0))

    first = read_dish_scale(image)
    second = read_dish_scale(image)

    assert first == second


def test_reads_an_off_centre_dish():
    """The Hough centre is the robust stage; nothing assumes a centred dish."""
    reading = read_dish_scale(_dish(outer_radius=250.0, centre=(390.0, 520.0)))

    assert reading.refusal is None
    assert reading.disc_diameter_px == pytest.approx(500.0, rel=0.01)


# --- the canonical value ---------------------------------------------------


def test_the_canonical_is_the_ninety_fifth_percentile_of_the_readings():
    readings = [0.01 * index for index in range(1, 101)]

    assert canonical_mm_per_px(readings) == pytest.approx(
        float(np.percentile(readings, 95))
    )


def test_the_canonical_refuses_an_empty_population():
    with pytest.raises(ValueError, match="at least one reading"):
        canonical_mm_per_px([])


def test_the_summary_reports_each_population_separately():
    rows = [
        {"population": "A", "mm_per_px": 0.08},
        {"population": "A", "mm_per_px": 0.09},
        {"population": "B", "mm_per_px": 0.13},
    ]

    summary = summarise(rows)

    assert set(summary.populations) == {"A", "B"}
    assert summary.populations["A"].count == 2
    assert summary.populations["B"].maximum == pytest.approx(0.13)
    assert summary.overall.count == 3


def test_the_summary_states_a_population_with_no_reading_as_zero():
    """A quarantine count is stated even when it is zero, never omitted."""
    rows = [
        {"population": "A", "mm_per_px": 0.08},
        {"population": "B", "mm_per_px": None, "refusal": "no_circle_found"},
    ]

    summary = summarise(rows)

    assert summary.quarantined["A"] == 0
    assert summary.quarantined["B"] == 1


# --- the committed record --------------------------------------------------


def _record() -> dict:
    return json.loads(RECORD_PATH.read_text(encoding="utf-8"))


def test_the_record_names_the_command_that_produced_it():
    """Self-describing, so reproducing it needs nothing but the record."""
    record = _record()

    assert record["command"] == "python scripts/measure_scale.py --version v1"


def test_the_record_names_the_dataset_version_and_the_manifest_digest():
    record = _record()

    assert record["dataset_version"] == "v1"
    assert len(record["manifest_digest"]) == 64
    assert record["dish_diameter_mm"] == DISH_DIAMETER_MM


def test_the_record_holds_one_row_per_photograph():
    photographs = _record()["photographs"]

    assert len(photographs) == 221
    assert len({row["image"] for row in photographs}) == 221
    assert {row["population"] for row in photographs} == {"A", "B", "C"}


def test_the_canonical_in_the_record_is_recomputed_from_its_own_rows():
    record = _record()
    readings = [
        row["mm_per_px"] for row in record["photographs"] if row["mm_per_px"] is not None
    ]

    assert record["canonical_mm_per_px"] == pytest.approx(
        canonical_mm_per_px(readings)
    )


def test_the_record_reports_each_population_separately():
    summary = _record()["summary"]

    assert set(summary["populations"]) == {"A", "B", "C"}
    for population in summary["populations"].values():
        for key in ("count", "minimum", "p5", "p50", "p95", "maximum"):
            assert key in population


def test_quarantine_names_every_photograph_that_got_no_scale():
    """Asserted on rows that hold a refusal, since the record holds none.

    Over the committed record both sides of the equality are empty, so this
    property has to be exercised on data that has something to lose.
    """
    rows = [
        {"image": "a.jpg", "population": "A", "mm_per_px": 0.08},
        {"image": "b.jpg", "population": "A", "mm_per_px": None},
        {"image": "c.jpg", "population": "B", "mm_per_px": None},
    ]

    summary = summarise(rows).as_dict()

    assert set(summary["quarantined_images"]) == {"b.jpg", "c.jpg"}
    assert summary["quarantined"] == {"A": 1, "B": 1}
    assert sum(summary["quarantined"].values()) == len(summary["quarantined_images"])


def test_the_record_states_a_quarantine_count_for_every_population():
    record = _record()

    named = {row["image"] for row in record["photographs"] if row["mm_per_px"] is None}
    assert named == set(record["summary"]["quarantined_images"])
    assert set(record["summary"]["quarantined"]) == {"A", "B", "C"}


def test_the_recorded_canonical_confirms_the_value_spec_0037_ships():
    """SPEC 0037 ships 0.130 mm/px; this is the recomputation it asked for.

    Within two per cent, which is the tolerance that leaves SPEC 0037's patch
    geometry standing: the patch side moves by the same fraction and the patch
    counts, which step in whole squares, do not move at all.
    """
    assert _record()["canonical_mm_per_px"] == pytest.approx(0.130, rel=0.02)


@real_only
def test_the_record_was_taken_over_the_manifest_on_disk():
    """Against the version's identity, which is its manifest before measuring.

    Not the file digest: the run writes its own result into those columns, so
    the file digest stops matching the moment the measurement lands.
    """
    assert _record()["manifest_digest"] == unmeasured_digest(REAL_VERSION)


def test_the_measurement_reproduces_from_the_recorded_command(tmp_path):
    """Two runs of the command over one version write the same bytes.

    Over a rendered version rather than the archive, so the criterion is checked
    wherever the suite runs. A reproducibility claim that could only be checked
    on the one machine holding the images would be the weakest kind of evidence
    for the one property the record exists to carry.
    """
    root = write_image_version(
        tmp_path,
        {
            "sample-1": [("dish", _dish(outer_radius=300.0))],
            "sample-2": [("dish", _dish(outer_radius=250.0))],
        },
    )
    measure_scale = _load_script("measure_scale")

    first, second = tmp_path / "first.json", tmp_path / "second.json"
    assert measure_scale.main(["--root", str(root), "--out", str(first)]) == 0
    assert measure_scale.main(["--root", str(root), "--out", str(second)]) == 0

    assert first.read_bytes() == second.read_bytes()
    written = json.loads(first.read_text(encoding="utf-8"))
    assert len(written["photographs"]) == 2
    assert written["canonical_mm_per_px"] > 0.0
    assert written["command"].startswith("python scripts/measure_scale.py --root ")


@real_only
@pytest.mark.parametrize("image_name", ["IMG_8231.png", "IMG_8100.png"])
def test_an_archive_photograph_reads_the_same_scale_under_reflection(image_name):
    """A mirrored photograph is the same dish at the same scale.

    The strongest property available without a ground truth, and the one that
    caught the reader measuring the soil boundary instead of the rim: the four
    dihedral views of one photograph disagreed by up to 2.6 % while every
    reading reported full ray coverage and a dispersion under 0.02.
    """
    path = next(REAL_VERSION.glob(f"images/*/{image_name}"))
    original = Image.open(path)
    views = [
        original,
        original.transpose(Image.FLIP_LEFT_RIGHT),
        original.transpose(Image.FLIP_TOP_BOTTOM),
        original.transpose(Image.ROTATE_180),
    ]

    readings = [read_dish_scale(view).mm_per_px for view in views]

    assert all(reading is not None for reading in readings)
    spread = max(readings) / min(readings) - 1.0
    assert spread < 0.01, f"{image_name} reads {spread:.2%} apart across reflections"


@real_only
def test_re_reading_an_archive_photograph_gives_the_recorded_value():
    """The record carries what the reader produces, not a rounded copy of it."""
    record = _record()
    row = next(
        entry for entry in record["photographs"] if entry["mm_per_px"] is not None
    )
    image = Image.open(REAL_VERSION / row["image"])

    reading = read_dish_scale(image)

    assert reading.mm_per_px == pytest.approx(row["mm_per_px"], rel=1e-12)


@real_only
def test_every_photograph_coarser_than_the_canonical_is_already_train_only():
    """The pool SPEC 0042 measures is untouched, so its MDE does not move."""
    record = _record()
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)
    train_only = train_only_sample_ids(manifest)
    canonical = record["canonical_mm_per_px"]
    by_image = {row.image: row.sample_id for row in manifest.rows}

    coarse = [
        entry
        for entry in record["photographs"]
        if entry["mm_per_px"] is not None and entry["mm_per_px"] > canonical
    ]

    assert coarse, "the canonical is a percentile; something must sit above it"
    assert all(by_image[entry["image"]] in train_only for entry in coarse)


def test_the_reader_is_pure_arithmetic_and_needs_no_tensorflow():
    """The measurement runs anywhere the manifest does; nothing imports TF.

    In a subprocess, because `sys.modules` is the whole session's and another
    module in this suite has already imported TensorFlow by the time this runs.
    Asserting against the shared table would test the run order, not the import.
    """
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import src.scale, sys; "
            "assert 'tensorflow' not in sys.modules, 'scale imported tensorflow'",
        ],
        cwd=ML_ROOT,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr


# --- the record is what fills the manifest ---------------------------------


def test_the_record_carries_the_centre_of_every_dish(tmp_path):
    """A diameter with no centre locates nothing, so the record carries both.

    The manifest is a build product (ADR 0019) and the record is committed, so
    the record is the only place a measurement survives a re-ingest. Leaving the
    centre out of it would mean the seven-minute reader run is the only way back
    to a grid position, every time the version is rebuilt.
    """
    root = write_image_version(
        tmp_path, {"sample-1": [("dish", _dish(outer_radius=300.0))]}
    )
    measure_scale = _load_script("measure_scale")
    out = tmp_path / "record.json"

    assert measure_scale.main(["--root", str(root), "--out", str(out)]) == 0

    row = json.loads(out.read_text(encoding="utf-8"))["photographs"][0]
    assert row["disc_centre_x_px"] == pytest.approx(450.0, abs=2.0)
    assert row["disc_centre_y_px"] == pytest.approx(450.0, abs=2.0)


def test_the_committed_record_carries_the_centre_of_every_photograph():
    photographs = _record()["photographs"]

    assert all("disc_centre_x_px" in row for row in photographs)
    assert all(
        row["disc_centre_y_px"] is not None
        for row in photographs
        if row["mm_per_px"] is not None
    )


def test_the_manifest_is_filled_from_the_record_without_reading_an_image(
    tmp_path, monkeypatch
):
    """Re-ingesting a version drops the columns; refilling them is arithmetic.

    The measurement costs seven minutes over the archive and the manifest is
    rebuilt whenever the version is, so the second and every later fill reads
    the committed record instead of the photographs.
    """
    root = write_image_version(
        tmp_path, {"sample-1": [("dish", _dish(outer_radius=300.0))]}
    )
    measure_scale = _load_script("measure_scale")
    record = tmp_path / "record.json"
    assert measure_scale.main(["--root", str(root), "--out", str(record)]) == 0

    def refuse(*args, **kwargs):
        raise AssertionError("--from-record must not open a photograph")

    monkeypatch.setattr(measure_scale.Image, "open", refuse)
    assert (
        measure_scale.main(
            ["--root", str(root), "--from-record", str(record)]
        )
        == 0
    )

    from src.manifest import SCALE_COLUMNS
    from tests.support import CLASSES

    row = read_manifest(root, CLASSES).rows[0]
    assert set(SCALE_COLUMNS) == set(row.scale)
    assert row.scale["disc_diameter_px"] == pytest.approx(600.0, abs=4.0)


def test_a_record_taken_over_another_manifest_is_refused(tmp_path):
    """The digest is what proves the rows describe these photographs."""
    root = write_image_version(
        tmp_path, {"sample-1": [("dish", _dish(outer_radius=300.0))]}
    )
    other = write_image_version(
        tmp_path / "other", {"sample-2": [("dish", _dish(outer_radius=250.0))]}
    )
    measure_scale = _load_script("measure_scale")
    record = tmp_path / "record.json"
    assert measure_scale.main(["--root", str(other), "--out", str(record)]) == 0

    assert (
        measure_scale.main(["--root", str(root), "--from-record", str(record)])
        == 1
    )


def test_the_recorded_digest_ignores_the_measurement_it_writes(tmp_path):
    """The digest says which data was measured, not whether it has been.

    `measure_scale.py` writes its result into the manifest, the way
    `admit_images.py --write` already writes the quality metrics, so the file
    bytes change and a digest over them would stop describing the version the
    moment the measurement landed. Including a run's own output in the identity
    of its input is what makes `--from-record` impossible after a re-ingest.
    """
    root = write_image_version(
        tmp_path, {"sample-1": [("dish", _dish(outer_radius=300.0))]}
    )
    measure_scale = _load_script("measure_scale")
    out = tmp_path / "record.json"
    before = unmeasured_digest(root)

    assert measure_scale.main(["--root", str(root), "--out", str(out)]) == 0

    assert unmeasured_digest(root) == before
    record = json.loads(out.read_text(encoding="utf-8"))
    assert record["manifest_digest"] == before
    assert read_manifest(root, CLASSES).rows[0].scale
