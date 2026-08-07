"""Soil image acceptance criteria — the reference implementation (SPEC 0030).

One criteria set governs both what enters the dataset and what the app is
allowed to produce (ADR 0009). This module is the Python half; the Dart half is
`lib/core/services/image_quality/`. The two agree by construction of the golden
file under `test/fixtures/image_quality/`, and any divergence fails both suites.

Everything here is pure arithmetic over pixels: no model, no I/O, no state.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional, Tuple

import numpy as np
from PIL import Image, ImageOps

# ITU-R BT.601 luma, on 8-bit channel values as float64, no rounding.
LUMA_R = 0.299
LUMA_G = 0.587
LUMA_B = 0.114

# Fixed points of the metric definitions. These are not thresholds and are not
# tunable: changing one changes what the metric means, so both languages and
# every calibration would have to move together.
DARK_CLIP_LUMA = 2.0
BRIGHT_CLIP_LUMA = 253.0
SPECULAR_LUMA = 250.0
SPECULAR_SATURATION = 0.10
DOWNSCALE_SIDE_PX = 512


class Criterion(str, Enum):
    """The seven criteria, in the order the report lists them."""

    BLUR = "blur"
    EXPOSURE = "exposure"
    CLIPPING = "clipping"
    CONTRAST = "contrast"
    COLOR_CAST = "colorCast"
    SPECULAR = "specular"
    RESOLUTION = "resolution"


class Verdict(str, Enum):
    OK = "ok"
    ADVISORY = "advisory"
    BLOCKING = "blocking"
    UNVALIDATED = "unvalidated"


#: Only these may block. The other three are advisory until calibrated against
#: real images; blocking on an uncalibrated criterion refuses legitimate work.
BLOCKING_CRITERIA = frozenset(
    {
        Criterion.BLUR,
        Criterion.EXPOSURE,
        Criterion.CLIPPING,
        Criterion.RESOLUTION,
    }
)


@dataclass(frozen=True)
class ImageQualityCriteria:
    """Thresholds.

    **Every default here is PROVISIONAL.** They are engineering starting points,
    not calibrated values: no real soil images exist to calibrate against
    (`docs/architecture/soil-classification.md` §4). They are a value object so
    a later phase can recalibrate without touching the analyzer, and so an audit
    run and a capture gate can be pinned to the same criteria.
    """

    min_blur_score: float = 100.0
    min_mean_luminance: float = 40.0
    max_mean_luminance: float = 215.0
    max_clipped_fraction: float = 0.05
    min_contrast_score: float = 20.0
    max_color_cast_score: float = 0.15
    max_specular_fraction: float = 0.10
    min_roi_side_px: int = 512


DEFAULT_CRITERIA = ImageQualityCriteria()


@dataclass(frozen=True)
class CriterionFailure:
    """One criterion that failed, with how far it missed."""

    criterion: Criterion
    severity: Verdict
    measured: float
    threshold: float
    margin: float


@dataclass(frozen=True)
class ImageQualityMetrics:
    blur_score: float
    mean_luminance: float
    clipped_fraction: float
    contrast_score: float
    color_cast_score: float
    specular_fraction: float
    roi_side_px: int
    downscale_applied: bool


@dataclass(frozen=True)
class ImageQualityReport:
    verdict: Verdict
    metrics: Optional[ImageQualityMetrics]
    failures: Tuple[CriterionFailure, ...]
    #: Why the analysis could not run. Set only for ``UNVALIDATED``, so a
    #: failure is reported rather than swallowed.
    unvalidated_reason: Optional[str] = None


def roi_bounds(width: int, height: int) -> Tuple[int, int, int]:
    """Return ``(x, y, side)`` of the largest centred square."""
    side = min(width, height)
    return ((width - side) // 2, (height - side) // 2, side)


def analyze(
    image: Image.Image, criteria: ImageQualityCriteria = DEFAULT_CRITERIA
) -> ImageQualityReport:
    """Measure [image] and return a verdict.

    A failure of the analyzer itself yields ``UNVALIDATED`` with its cause
    attached, never ``BLOCKING`` and never an exception: a crashed checker must
    not reject a valid sample, and the caller must not be able to forget the
    case.
    """
    try:
        metrics = measure(image)
    except Exception as error:  # noqa: BLE001 - converted to a verdict, not swallowed
        return ImageQualityReport(
            verdict=Verdict.UNVALIDATED,
            metrics=None,
            failures=(),
            unvalidated_reason=f"{type(error).__name__}: {error}",
        )

    failures = evaluate(metrics, criteria)
    if any(failure.severity is Verdict.BLOCKING for failure in failures):
        verdict = Verdict.BLOCKING
    elif failures:
        verdict = Verdict.ADVISORY
    else:
        verdict = Verdict.OK
    return ImageQualityReport(verdict=verdict, metrics=metrics, failures=failures)


def measure(image: Image.Image) -> ImageQualityMetrics:
    """Compute the seven metrics over the ROI. Raises on an unusable image."""
    baked = ImageOps.exif_transpose(image)
    rgb = np.asarray(baked.convert("RGB"), dtype=np.float64)
    height, width = rgb.shape[0], rgb.shape[1]
    x, y, side = roi_bounds(width, height)
    if side <= 0:
        raise ValueError(f"image has a zero-length side: {width}x{height}")

    roi = rgb[y : y + side, x : x + side, :]
    red = roi[:, :, 0]
    green = roi[:, :, 1]
    blue = roi[:, :, 2]
    luma = LUMA_R * red + LUMA_G * green + LUMA_B * blue

    clipped = (luma <= DARK_CLIP_LUMA) | (luma >= BRIGHT_CLIP_LUMA)

    channel_means = (float(red.mean()), float(green.mean()), float(blue.mean()))
    cast = max(
        abs(channel_means[0] - channel_means[1]),
        abs(channel_means[0] - channel_means[2]),
        abs(channel_means[1] - channel_means[2]),
    )

    brightest = roi.max(axis=2)
    darkest = roi.min(axis=2)
    saturation = np.divide(
        brightest - darkest,
        brightest,
        out=np.zeros_like(brightest),
        where=brightest > 0.0,
    )
    specular = (luma >= SPECULAR_LUMA) & (saturation <= SPECULAR_SATURATION)

    downscale_applied = side > DOWNSCALE_SIDE_PX
    blur_plane = (
        box_downscale(luma, DOWNSCALE_SIDE_PX) if downscale_applied else luma
    )

    return ImageQualityMetrics(
        blur_score=laplacian_variance(blur_plane),
        mean_luminance=float(luma.mean()),
        clipped_fraction=float(clipped.mean()),
        contrast_score=float(luma.std()),
        color_cast_score=cast / 255.0,
        specular_fraction=float(specular.mean()),
        roi_side_px=side,
        downscale_applied=downscale_applied,
    )


def box_downscale(plane: np.ndarray, target: int) -> np.ndarray:
    """Area-weighted average downscale of a square plane to ``target`` a side.

    Defined arithmetically rather than delegated to a library resize, because
    the two languages' bilinear filters are different algorithms and would never
    agree to the conformance tolerance. An area filter is also what makes
    ``blur_score`` comparable across capture resolutions: a point-sampled
    bilinear ignores most source pixels when shrinking, so a high-frequency
    pattern would alias differently at each source size.

    Horizontal pass first, then vertical, matching SPEC 0030.
    """
    weights = _area_weights(plane.shape[0], target)
    return weights @ (plane @ weights.T)


def _area_weights(source: int, target: int) -> np.ndarray:
    """Row ``j`` holds each source index's fractional coverage of output ``j``."""
    scale = source / target
    weights = np.zeros((target, source), dtype=np.float64)
    for j in range(target):
        start = j * scale
        end = (j + 1) * scale
        first = int(np.floor(start))
        last = min(int(np.ceil(end)), source)
        for i in range(first, last):
            overlap = min(end, i + 1.0) - max(start, float(i))
            if overlap > 0.0:
                weights[j, i] = overlap / scale
    return weights


def laplacian_variance(plane: np.ndarray) -> float:
    """Population variance of the 3x3 Laplacian over interior pixels only.

    Kernel ``[[0, 1, 0], [1, -4, 1], [0, 1, 0]]``. No padding and no border
    extension, so an invented edge cannot contribute to the score.
    """
    if plane.shape[0] < 3 or plane.shape[1] < 3:
        raise ValueError(f"plane too small for a 3x3 kernel: {plane.shape}")
    centre = plane[1:-1, 1:-1]
    response = (
        plane[:-2, 1:-1]
        + plane[2:, 1:-1]
        + plane[1:-1, :-2]
        + plane[1:-1, 2:]
        - 4.0 * centre
    )
    return float(response.var())


def evaluate(
    metrics: ImageQualityMetrics, criteria: ImageQualityCriteria
) -> Tuple[CriterionFailure, ...]:
    """Every failing criterion, in metric-table order.

    Never short-circuits: the caller must be able to name everything that needs
    fixing in one retake.
    """
    failures = []

    if metrics.blur_score < criteria.min_blur_score:
        failures.append(
            _failure(Criterion.BLUR, metrics.blur_score, criteria.min_blur_score)
        )

    if metrics.mean_luminance < criteria.min_mean_luminance:
        failures.append(
            _failure(
                Criterion.EXPOSURE,
                metrics.mean_luminance,
                criteria.min_mean_luminance,
            )
        )
    elif metrics.mean_luminance > criteria.max_mean_luminance:
        failures.append(
            _failure(
                Criterion.EXPOSURE,
                metrics.mean_luminance,
                criteria.max_mean_luminance,
            )
        )

    if metrics.clipped_fraction > criteria.max_clipped_fraction:
        failures.append(
            _failure(
                Criterion.CLIPPING,
                metrics.clipped_fraction,
                criteria.max_clipped_fraction,
            )
        )

    if metrics.contrast_score < criteria.min_contrast_score:
        failures.append(
            _failure(
                Criterion.CONTRAST,
                metrics.contrast_score,
                criteria.min_contrast_score,
            )
        )

    if metrics.color_cast_score > criteria.max_color_cast_score:
        failures.append(
            _failure(
                Criterion.COLOR_CAST,
                metrics.color_cast_score,
                criteria.max_color_cast_score,
            )
        )

    if metrics.specular_fraction > criteria.max_specular_fraction:
        failures.append(
            _failure(
                Criterion.SPECULAR,
                metrics.specular_fraction,
                criteria.max_specular_fraction,
            )
        )

    if metrics.roi_side_px < criteria.min_roi_side_px:
        failures.append(
            _failure(
                Criterion.RESOLUTION,
                float(metrics.roi_side_px),
                float(criteria.min_roi_side_px),
            )
        )

    return tuple(failures)


def _failure(
    criterion: Criterion, measured: float, threshold: float
) -> CriterionFailure:
    return CriterionFailure(
        criterion=criterion,
        severity=(
            Verdict.BLOCKING if criterion in BLOCKING_CRITERIA else Verdict.ADVISORY
        ),
        measured=measured,
        threshold=threshold,
        margin=abs(measured - threshold),
    )
