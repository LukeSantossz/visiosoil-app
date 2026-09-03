"""Acceptance criteria for the dish-rim scale reader (SPEC 0052).

Each test name matches an acceptance criterion in
`docs/specs/0052-read-the-dish-rim-and-recompute-the-canonical-scale.md`.

The fixtures are rendered circles, so most of the suite runs without the
archive. The dataset-gated tests at the end assert the committed measurement
record against the version it was taken over; SPEC 0043 requires that no
criterion be covered only by those, and none is.
"""

import json
import math
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from src.manifest import ARCHIVE_CLASSES, read_manifest, train_only_sample_ids
from src.scale import (
    DISH_DIAMETER_MM,
    CanonicalScale,
    ScaleRefusal,
    canonical_mm_per_px,
    read_dish_scale,
    summarise,
)

ML_ROOT = Path(__file__).resolve().parents[1]
RECORD_PATH = ML_ROOT / "measurements" / "dish-scale-v1.json"
REAL_VERSION = ML_ROOT / "data" / "datasets" / "v1"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file(),
    reason="the ingested version is not present; its images are not tracked",
)


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


def test_reads_the_rim_of_a_synthetic_dish_within_one_percent():
    reading = read_dish_scale(_dish(outer_radius=300.0))

    assert reading.refusal is None
    assert reading.disc_diameter_px == pytest.approx(600.0, rel=0.01)
    assert reading.mm_per_px == pytest.approx(DISH_DIAMETER_MM / 600.0, rel=0.01)


def test_measures_the_outer_circle_not_the_inner_one():
    """The soil disc is the strongest edge; the rim is the reference."""
    reading = read_dish_scale(_dish(outer_radius=300.0, inner_radius=220.0))

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


def test_quarantine_is_reported_by_name_and_per_population():
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
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)

    assert _record()["manifest_digest"] == manifest.digest


@real_only
def test_the_measurement_reproduces_from_the_recorded_command():
    """Re-reading one photograph reproduces the value the record carries."""
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
    """The measurement runs anywhere the manifest does; nothing imports TF."""
    import sys

    import src.scale  # noqa: F401  - imported for its side effects only

    assert "tensorflow" not in sys.modules


def test_the_canonical_scale_is_a_value_object_naming_its_population():
    canonical = CanonicalScale(mm_per_px=0.1298, count=221, percentile=95.0)

    assert canonical.mm_per_px == pytest.approx(0.1298)
    assert canonical.count == 221
    assert math.isclose(canonical.percentile, 95.0)
