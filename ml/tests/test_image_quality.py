"""Acceptance criteria for the soil image quality analyzer (SPEC 0030).

Each test name matches an acceptance criterion in
`docs/specs/0030-soil-image-acceptance-criteria.md`.
"""

import io
import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageFilter

from src.image_quality import (
    DEFAULT_CRITERIA,
    Criterion,
    ImageQualityCriteria,
    Verdict,
    analyze,
    roi_bounds,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = REPO_ROOT / "test" / "fixtures" / "image_quality"
GOLDEN_PATH = FIXTURE_DIR / "golden.json"

SIDE = 640


# --- fixture builders: deterministic, no randomness ------------------------


def _to_image(array: np.ndarray) -> Image.Image:
    return Image.fromarray(array.astype(np.uint8), mode="RGB")


def _flat(side: int, value: int) -> np.ndarray:
    return np.full((side, side, 3), value, dtype=np.uint8)


def _checkerboard(side: int, low: int, high: int, cell: int = 8) -> np.ndarray:
    ys, xs = np.mgrid[0:side, 0:side]
    mask = ((xs // cell) + (ys // cell)) % 2 == 0
    plane = np.where(mask, high, low)
    return np.dstack([plane, plane, plane]).astype(np.uint8)


def _failed_criteria(report) -> set:
    return {failure.criterion for failure in report.failures}


# --- ROI geometry ----------------------------------------------------------


def test_roi_is_largest_centred_square():
    assert roi_bounds(400, 300) == (50, 0, 300)
    assert roi_bounds(300, 400) == (0, 50, 300)
    assert roi_bounds(300, 300) == (0, 0, 300)


def test_roi_side_is_reported():
    report = analyze(_to_image(_checkerboard(SIDE, 60, 200)))
    assert report.metrics.roi_side_px == SIDE

    wide = np.repeat(_checkerboard(SIDE, 60, 200), 2, axis=1)
    assert wide.shape[1] == 2 * SIDE
    assert analyze(_to_image(wide)).metrics.roi_side_px == SIDE


def test_roi_side_below_minimum_is_blocking():
    small = _checkerboard(256, 60, 200, cell=4)
    report = analyze(_to_image(small))
    assert report.verdict is Verdict.BLOCKING
    assert Criterion.RESOLUTION in _failed_criteria(report)


# --- blur ------------------------------------------------------------------


def test_blur_is_resolution_independent():
    """The fixed 512 px downscale must run before the Laplacian."""
    large = analyze(_to_image(_checkerboard(2048, 60, 200, cell=64)))
    small = analyze(_to_image(_checkerboard(1024, 60, 200, cell=32)))
    ratio = large.metrics.blur_score / small.metrics.blur_score
    assert 0.95 <= ratio <= 1.05


def test_blur_separates_sharp_from_blurred():
    sharp_pixels = _to_image(_checkerboard(SIDE, 60, 200))
    blurred_pixels = sharp_pixels.filter(ImageFilter.GaussianBlur(radius=6))

    sharp = analyze(sharp_pixels)
    blurred = analyze(blurred_pixels)

    assert sharp.metrics.blur_score > blurred.metrics.blur_score
    assert Criterion.BLUR not in _failed_criteria(sharp)
    assert Criterion.BLUR in _failed_criteria(blurred)
    assert blurred.verdict is Verdict.BLOCKING


# --- exposure and clipping -------------------------------------------------


def test_exposure_bounds_are_two_sided():
    dark = analyze(_to_image(_checkerboard(SIDE, 5, 35)))
    bright = analyze(_to_image(_checkerboard(SIDE, 225, 248)))
    mid = analyze(_to_image(_checkerboard(SIDE, 60, 200)))

    assert dark.verdict is Verdict.BLOCKING
    assert Criterion.EXPOSURE in _failed_criteria(dark)
    assert bright.verdict is Verdict.BLOCKING
    assert Criterion.EXPOSURE in _failed_criteria(bright)
    assert Criterion.EXPOSURE not in _failed_criteria(mid)


def test_clipping_is_detected():
    """20% of pixels at 255 gives exactly 0.20 and blocks."""
    pixels = _checkerboard(SIDE, 96, 160, cell=4)
    pixels[:, ::5] = 255
    report = analyze(_to_image(pixels))

    assert report.metrics.clipped_fraction == pytest.approx(0.20, abs=1e-12)
    assert report.verdict is Verdict.BLOCKING
    assert Criterion.CLIPPING in _failed_criteria(report)


# --- the advisory criteria -------------------------------------------------


def test_low_contrast_is_advisory():
    """Low amplitude fails contrast; sharp edges still clear the blur bound."""
    pixels = _checkerboard(SIDE, 113, 143, cell=4)
    report = analyze(_to_image(pixels))

    assert report.metrics.contrast_score < DEFAULT_CRITERIA.min_contrast_score
    assert Criterion.CONTRAST in _failed_criteria(report)
    assert Criterion.BLUR not in _failed_criteria(report)
    assert report.verdict is Verdict.ADVISORY


def test_colour_cast_is_advisory():
    """A red channel mean 60 above the others scores exactly 60/255."""
    pixels = _checkerboard(SIDE, 60, 180, cell=4)
    pixels[:, :, 0] = np.clip(pixels[:, :, 0].astype(np.int32) + 60, 0, 255)
    report = analyze(_to_image(pixels))

    assert report.metrics.color_cast_score == pytest.approx(60 / 255, abs=1e-12)
    assert Criterion.COLOR_CAST in _failed_criteria(report)
    assert report.verdict is Verdict.ADVISORY


def test_specular_is_advisory():
    """15% of the ROI bright and unsaturated, below the clipping bound."""
    pixels = _checkerboard(SIDE, 100, 160, cell=4)
    bright_rows = int(SIDE * 0.15)
    pixels[:bright_rows, :, :] = 251
    report = analyze(_to_image(pixels))

    assert report.metrics.specular_fraction == pytest.approx(0.15, abs=1e-12)
    assert report.metrics.clipped_fraction == 0.0
    assert Criterion.SPECULAR in _failed_criteria(report)
    assert report.verdict is Verdict.ADVISORY


# --- verdict composition ---------------------------------------------------


def test_blocking_outranks_advisory():
    pixels = _checkerboard(SIDE, 60, 180, cell=4)
    pixels[:, :, 0] = np.clip(pixels[:, :, 0].astype(np.int32) + 60, 0, 255)
    blurred = _to_image(pixels).filter(ImageFilter.GaussianBlur(radius=6))
    report = analyze(blurred)

    failed = _failed_criteria(report)
    assert Criterion.BLUR in failed
    assert Criterion.COLOR_CAST in failed
    assert report.verdict is Verdict.BLOCKING


def test_all_failing_criteria_are_reported():
    """A flat dark fill fails exposure, contrast and blur at once."""
    report = analyze(_to_image(_flat(SIDE, 12)))
    failed = _failed_criteria(report)

    assert {Criterion.EXPOSURE, Criterion.CONTRAST, Criterion.BLUR} <= failed
    for failure in report.failures:
        assert failure.measured == failure.measured  # not NaN
        assert failure.margin > 0.0


def test_ok_report_lists_no_failures():
    report = analyze(_to_image(_checkerboard(SIDE, 60, 200, cell=4)))
    assert report.verdict is Verdict.OK
    assert report.failures == ()


def test_analyzer_failure_is_unvalidated():
    report = analyze(Image.new("RGB", (0, 0)))
    assert report.verdict is Verdict.UNVALIDATED
    assert report.metrics is None
    assert report.failures == ()


def test_criteria_are_injectable():
    """A fixture between the custom and the default threshold flips verdict."""
    pixels = _to_image(_checkerboard(SIDE, 60, 200, cell=4))
    default_report = analyze(pixels)
    assert default_report.verdict is Verdict.OK

    measured = default_report.metrics.contrast_score
    strict = ImageQualityCriteria(min_contrast_score=measured + 10.0)
    strict_report = analyze(pixels, strict)

    assert strict_report.verdict is Verdict.ADVISORY
    assert Criterion.CONTRAST in _failed_criteria(strict_report)


def test_orientation_is_baked_before_cropping():
    """An EXIF-tagged image must measure as its already-rotated pixels do."""
    tall = np.repeat(_checkerboard(SIDE, 60, 200, cell=4), 2, axis=0)
    rotated = np.rot90(tall, k=-1).copy()

    source = _to_image(tall)
    exif = source.getexif()
    exif[274] = 6  # Orientation: rotate 90 degrees clockwise

    buffer = io.BytesIO()
    source.save(buffer, format="PNG", exif=exif)
    buffer.seek(0)
    tagged = Image.open(buffer)
    assert tagged.getexif().get(274) == 6

    baked = analyze(tagged).metrics
    reference = analyze(_to_image(rotated)).metrics

    assert baked.roi_side_px == reference.roi_side_px
    assert baked.mean_luminance == pytest.approx(
        reference.mean_luminance, rel=1e-9
    )
    assert baked.blur_score == pytest.approx(reference.blur_score, rel=1e-9)


# --- cross-language conformance -------------------------------------------


def _golden():
    if not GOLDEN_PATH.exists():
        pytest.fail(
            f"{GOLDEN_PATH} is missing. Regenerate it with "
            "`python scripts/generate_image_quality_golden.py`."
        )
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


def test_python_matches_golden():
    golden = _golden()
    for entry in golden["fixtures"]:
        image = Image.open(FIXTURE_DIR / entry["file"])
        report = analyze(image)

        assert report.verdict.value == entry["verdict"], entry["file"]
        for name, expected in entry["metrics"].items():
            actual = getattr(report.metrics, name)
            if isinstance(expected, bool) or isinstance(expected, int):
                assert actual == expected, f"{entry['file']}.{name}"
            else:
                assert actual == pytest.approx(
                    expected, rel=1e-9
                ), f"{entry['file']}.{name}"


def test_golden_covers_every_criterion():
    """Each criterion is the sole failure of at least one fixture."""
    golden = _golden()
    sole = set()
    for entry in golden["fixtures"]:
        if len(entry["failures"]) == 1:
            sole.add(entry["failures"][0]["criterion"])

    missing = {c.value for c in Criterion} - sole
    assert not missing, f"no fixture isolates: {sorted(missing)}"


def test_golden_fixtures_are_not_near_a_threshold():
    """Verdicts must not be sensitive to floating-point noise."""
    golden = _golden()
    for entry in golden["fixtures"]:
        for name, distance in entry["threshold_distance"].items():
            assert distance > 1e-6, f"{entry['file']}.{name} sits on a threshold"
