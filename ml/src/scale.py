"""The dish-rim scale reader — millimetres per pixel from a known circle.

Textural class is a statement about particle size, and particle size in an
image is meaningless without a known scale (ADR 0017). The archive photographs
soil in a 90 mm Petri dish, so the dish is the reference and this module reads
it: a circular Hough vote over edge orientations for the centre, then the
outermost strong radial edge for the rim.

The reference is the **outer** glass rim and never the soil disc. The soil
boundary is by far the strongest edge in these photographs and is trivially
found, but its physical diameter is only the dish's inner diameter when the dish
is full, and the archive holds under-filled dishes. A reference whose size
depends on how much soil was poured is not a reference (SPEC 0052).

A photograph whose rim cannot be fitted is **refused by name**, never given a
default scale: a guessed scale rescales the input silently and the
classification is then confidently wrong.

Everything here is pure arithmetic over pixels: no model, no TensorFlow, no
randomness and no seed. The application side reads an A4 sheet by a different
operator, and ADR 0017 records why the two sides do not share one reader.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Iterable, Mapping, Optional, Sequence

import numpy as np
from PIL import Image, ImageOps

from src.image_quality import LUMA_B, LUMA_G, LUMA_R

#: Confirmed by the project owner on 2026-08-25, and the outer diameter. Every
#: absolute millimetre figure in this project rests on it.
DISH_DIAMETER_MM = 90.0

#: The percentile that defines the canonical scale, over millimetres per pixel.
#: SPEC 0037 calls it `p5` because it is the fifth percentile of *pixels per
#: millimetre*; over millimetres per pixel the same cut is the ninety-fifth.
#: Normalising toward a coarser scale destroys detail a more distant camera
#: would also not have resolved, while normalising toward a finer one invents
#: grain structure that was never photographed, so the canonical is set by the
#: coarsest photograph retained rather than by the median.
CANONICAL_PERCENTILE = 95.0

# --- fixed points of the operator -----------------------------------------
# These are not tunable thresholds. Changing one changes what the reader
# measures, so a change moves every recorded reading and needs its own record.

#: The Hough vote runs here. Coarse on purpose: the accumulator is quadratic in
#: the side, and the centre needs to be right to a pixel of this grid, not of
#: the photograph.
COARSE_SIDE_PX = 256
#: The radial search runs here, which is where the radius is actually measured.
REFINE_SIDE_PX = 768
#: Rays cast from the centre. Half a degree apart, so a rim spanning one pixel
#: of the refinement grid is still crossed by several rays.
RAY_COUNT = 720
#: Radial sampling step, in pixels of the refinement grid.
RAY_STEP_PX = 0.5

#: The fraction of pixels that vote. The rim is a long structure, so it does
#: not need a low threshold to be found, and a low one lets texture vote.
EDGE_VOTE_FRACTION = 0.06
#: Below this Sobel magnitude there is no edge to vote with, on luma scaled to
#: [0, 1]. A blank frame scores zero and is refused rather than fitted.
MIN_SOBEL_MAGNITUDE = 0.02
#: The same guard on the radial profile, which is a median over rays of a
#: half-pixel difference and so lives an order of magnitude below the Sobel
#: magnitude. It is a second net rather than the main one: a frame with no edge
#: at all has already been refused by the vote.
MIN_PROFILE_EDGE = 0.002
#: The profile is the median over rays, so a radius counts only when most of
#: the circumference agrees there is an edge at it. That is the property that
#: makes the profile a circle detector rather than an edge detector.
PROFILE_QUANTILE = 50.0
#: Used only to name a refusal, never to measure. A boundary that a minority of
#: rays agree on is a boundary that is not a circle, and telling that apart from
#: a frame holding no boundary at all is worth one extra pass: the two have
#: different remedies.
DIAGNOSTIC_QUANTILE = 90.0
#: A radial position counts as the rim when the median edge strength there
#: reaches this share of the profile's peak.
RIM_STRENGTH_FRACTION = 0.35
#: Each ray is refined within this fraction of the rim radius.
RIM_REFINE_BAND = 0.06
#: A ray has found the rim when its strongest edge inside the band reaches this
#: share of the profile's peak.
RAY_STRENGTH_FRACTION = 0.30

#: Radii searched, as a fraction of the shorter image side. A dish smaller than
#: the floor carries too few pixels to measure and one larger than the ceiling
#: is cropped by the frame.
MIN_RADIUS_FRACTION = 0.18
MAX_RADIUS_FRACTION = 0.52

#: Refusal thresholds. A rim whose per-ray radii disperse beyond the first, or
#: which fewer than the second of the rays could find, is not a circle this
#: reader is entitled to call 90 mm. Both sit above every value the archive
#: produces rather than below a calibrated one; SPEC 0052 records that.
MAX_RIM_DISPERSION = 0.06
MIN_RAY_COVERAGE = 0.70


class ScaleRefusal(str, Enum):
    """Why a photograph received no scale. Never a fallback, always a name."""

    NO_CIRCLE_FOUND = "no_circle_found"
    INCONSISTENT_RIM = "inconsistent_rim"


@dataclass(frozen=True)
class ScaleReading:
    """One photograph's scale, or the named reason it has none.

    `mm_per_px` and `disc_diameter_px` are `None` on every refusal, so a caller
    cannot read a number that was not measured.
    """

    mm_per_px: Optional[float]
    disc_diameter_px: Optional[float]
    centre_x_px: Optional[float]
    centre_y_px: Optional[float]
    #: Median absolute deviation of the per-ray rim radii, over the radius.
    rim_dispersion: float
    #: The share of rays that found the rim.
    ray_coverage: float
    refusal: Optional[ScaleRefusal] = None


@dataclass(frozen=True)
class CanonicalScale:
    """The contract value, with the population it was taken over."""

    mm_per_px: float
    count: int
    percentile: float


@dataclass(frozen=True)
class ScaleDistribution:
    """The shape of one population's readings."""

    count: int
    minimum: Optional[float]
    p5: Optional[float]
    p50: Optional[float]
    p95: Optional[float]
    maximum: Optional[float]

    def as_dict(self) -> dict:
        return {
            "count": self.count,
            "minimum": self.minimum,
            "p5": self.p5,
            "p50": self.p50,
            "p95": self.p95,
            "maximum": self.maximum,
        }


@dataclass(frozen=True)
class ScaleSummary:
    """Every population's distribution, and what each one lost."""

    overall: ScaleDistribution
    populations: Mapping[str, ScaleDistribution]
    quarantined: Mapping[str, int]
    quarantined_images: tuple[str, ...]

    def as_dict(self) -> dict:
        return {
            "overall": self.overall.as_dict(),
            "populations": {
                name: distribution.as_dict()
                for name, distribution in sorted(self.populations.items())
            },
            "quarantined": dict(sorted(self.quarantined.items())),
            "quarantined_images": list(self.quarantined_images),
        }


def read_dish_scale(image: Image.Image) -> ScaleReading:
    """Measure millimetres per pixel from the dish rim, or refuse by name."""
    baked = ImageOps.exif_transpose(image).convert("RGB")
    coarse, coarse_scale = _luma_at(baked, COARSE_SIDE_PX)
    shorter = min(coarse.shape)
    min_radius = MIN_RADIUS_FRACTION * shorter
    max_radius = MAX_RADIUS_FRACTION * shorter
    centre = _hough_centre(coarse, min_radius, max_radius)
    if centre is None:
        return _refused(ScaleRefusal.NO_CIRCLE_FOUND)

    fine, fine_scale = _luma_at(baked, REFINE_SIDE_PX)
    lift = fine_scale / coarse_scale
    centre_y, centre_x = centre[0] * lift, centre[1] * lift
    search_from = min_radius * lift * 0.7
    search_to = min(max_radius * lift * 1.25, _farthest_corner(fine, centre_y, centre_x))
    if search_to <= search_from + RAY_STEP_PX * 4:
        return _refused(ScaleRefusal.NO_CIRCLE_FOUND)

    # Pass one locates the centre. The vote is only as precise as its coarse
    # grid, and a centre wrong by a few pixels smears every concentric edge into
    # one blob — which would then be measured instead of the rim. So the
    # strongest structure, whichever of the concentric circles it is, is fitted
    # first and its centre is used for the measurement.
    located = _fit_edge(
        fine, centre_y, centre_x, search_from, search_to, outermost=False
    )
    if located is None:
        return _diagnose(fine, centre_y, centre_x, search_from, search_to)
    centre_y, centre_x = located.centre_y, located.centre_x

    # Pass two measures the rim: the outermost radius the profile still calls an
    # edge, refined per ray and fitted as a circle.
    rim = _fit_edge(fine, centre_y, centre_x, search_from, search_to, outermost=True)
    if rim is None:
        return _diagnose(fine, centre_y, centre_x, search_from, search_to)
    if rim.dispersion > MAX_RIM_DISPERSION or rim.coverage < MIN_RAY_COVERAGE:
        return _refused(
            ScaleRefusal.INCONSISTENT_RIM,
            rim_dispersion=rim.dispersion,
            ray_coverage=rim.coverage,
        )

    if rim.radius <= 0.0:
        return _refused(ScaleRefusal.NO_CIRCLE_FOUND, ray_coverage=rim.coverage)

    diameter_px = 2.0 * rim.radius / fine_scale
    return ScaleReading(
        mm_per_px=DISH_DIAMETER_MM / diameter_px,
        disc_diameter_px=diameter_px,
        centre_x_px=rim.centre_x / fine_scale,
        centre_y_px=rim.centre_y / fine_scale,
        rim_dispersion=rim.dispersion,
        ray_coverage=rim.coverage,
    )


def canonical_mm_per_px(
    readings: Sequence[float], percentile: float = CANONICAL_PERCENTILE
) -> float:
    """Return the canonical scale of a population of readings.

    Raises:
        ValueError: If the population is empty. A canonical derived from no
            reading would be a number nothing measured.
    """
    values = [float(reading) for reading in readings]
    if not values:
        raise ValueError(
            "a canonical scale needs at least one reading; the population has none"
        )
    return float(np.percentile(values, percentile))


def summarise(rows: Iterable[Mapping]) -> ScaleSummary:
    """Summarise per-photograph rows overall and per capture population.

    A population that produced no reading is still reported, with a zero count
    and a stated quarantine, because a population missing from a summary reads
    as a population that had nothing to report.
    """
    materialised = list(rows)
    populations = sorted({str(row.get("population", "")) for row in materialised})

    per_population: dict[str, ScaleDistribution] = {}
    quarantined: dict[str, int] = {}
    refused_images: list[str] = []
    for name in populations:
        subset = [row for row in materialised if str(row.get("population", "")) == name]
        readings = [
            float(row["mm_per_px"])
            for row in subset
            if row.get("mm_per_px") is not None
        ]
        per_population[name] = _distribution(readings)
        quarantined[name] = len(subset) - len(readings)
        refused_images.extend(
            str(row.get("image", ""))
            for row in subset
            if row.get("mm_per_px") is None
        )

    overall = _distribution(
        [
            float(row["mm_per_px"])
            for row in materialised
            if row.get("mm_per_px") is not None
        ]
    )
    return ScaleSummary(
        overall=overall,
        populations=per_population,
        quarantined=quarantined,
        quarantined_images=tuple(refused_images),
    )


# --- the operator, stage by stage ------------------------------------------


def _luma_at(image: Image.Image, side: int) -> tuple[np.ndarray, float]:
    """Return BT.601 luma in [0, 1] at `side` on the longer edge, and the ratio.

    The luma is the one `src.image_quality` defines, so the two operators cannot
    disagree about what grey means.
    """
    width, height = image.size
    ratio = side / max(width, height)
    resized = image.resize(
        (max(1, round(width * ratio)), max(1, round(height * ratio))),
        Image.BILINEAR,
    )
    rgb = np.asarray(resized, dtype=np.float64) / 255.0
    luma = LUMA_R * rgb[..., 0] + LUMA_G * rgb[..., 1] + LUMA_B * rgb[..., 2]
    return luma, ratio


def _sobel(plane: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    horizontal = np.array([[-1.0, 0.0, 1.0], [-2.0, 0.0, 2.0], [-1.0, 0.0, 1.0]])
    vertical = horizontal.T
    gradient_x = _convolve3(plane, horizontal)
    gradient_y = _convolve3(plane, vertical)
    return gradient_x, gradient_y, np.hypot(gradient_x, gradient_y)


def _convolve3(plane: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    padded = np.pad(plane, 1, mode="edge")
    height, width = plane.shape
    out = np.zeros_like(plane)
    for row in range(3):
        for column in range(3):
            out += kernel[row, column] * padded[row : row + height, column : column + width]
    return out


def _hough_centre(
    plane: np.ndarray, min_radius: float, max_radius: float
) -> Optional[tuple[float, float]]:
    """Return the centre every concentric edge agrees on, or None.

    The soil boundary, the inner wall and the outer rim are concentric, so all
    three vote for one centre. That is what makes the centre the robust stage
    and the radius the delicate one, rather than the other way round.
    """
    if max_radius <= min_radius:
        return None
    gradient_x, gradient_y, magnitude = _sobel(plane)
    if float(magnitude.max()) < MIN_SOBEL_MAGNITUDE:
        return None

    threshold = float(np.quantile(magnitude, 1.0 - EDGE_VOTE_FRACTION))
    rows, columns = np.nonzero(magnitude >= max(threshold, MIN_SOBEL_MAGNITUDE))
    if rows.size == 0:
        return None
    norm = magnitude[rows, columns]
    unit_y = gradient_y[rows, columns] / norm
    unit_x = gradient_x[rows, columns] / norm

    height, width = plane.shape
    accumulator = np.zeros((height, width), dtype=np.float64)
    radii = np.arange(round(min_radius), round(max_radius) + 1, 1.0)
    for sign in (1.0, -1.0):
        for radius in radii:
            candidate_y = np.rint(rows + sign * radius * unit_y).astype(np.int64)
            candidate_x = np.rint(columns + sign * radius * unit_x).astype(np.int64)
            inside = (
                (candidate_y >= 0)
                & (candidate_y < height)
                & (candidate_x >= 0)
                & (candidate_x < width)
            )
            np.add.at(accumulator, (candidate_y[inside], candidate_x[inside]), 1.0)

    smoothed = _convolve3(accumulator, np.ones((3, 3)))
    flat = int(np.argmax(smoothed))
    return float(flat // width), float(flat % width)


def _radial_samples(
    plane: np.ndarray, centre_y: float, centre_x: float, start: float, stop: float
) -> tuple[np.ndarray, np.ndarray]:
    """Sample `plane` along RAY_COUNT rays, bilinearly, as (radius, ray)."""
    angles = np.linspace(0.0, 2.0 * np.pi, RAY_COUNT, endpoint=False)
    radii = np.arange(start, stop, RAY_STEP_PX)
    radius_grid, angle_grid = np.meshgrid(radii, angles, indexing="ij")
    ys = centre_y + radius_grid * np.sin(angle_grid)
    xs = centre_x + radius_grid * np.cos(angle_grid)

    height, width = plane.shape
    inside = (ys >= 0.0) & (ys < height - 1) & (xs >= 0.0) & (xs < width - 1)
    y0 = np.clip(ys.astype(np.int64), 0, height - 2)
    x0 = np.clip(xs.astype(np.int64), 0, width - 2)
    dy = ys - y0
    dx = xs - x0
    values = (
        plane[y0, x0] * (1.0 - dy) * (1.0 - dx)
        + plane[y0 + 1, x0] * dy * (1.0 - dx)
        + plane[y0, x0 + 1] * (1.0 - dy) * dx
        + plane[y0 + 1, x0 + 1] * dy * dx
    )
    return radii, np.where(inside, values, np.nan)


@dataclass(frozen=True)
class _FittedCircle:
    """One circle fitted to the edge points found along the rays."""

    centre_y: float
    centre_x: float
    radius: float
    dispersion: float
    coverage: float


def _fit_edge(
    plane: np.ndarray,
    centre_y: float,
    centre_x: float,
    search_from: float,
    search_to: float,
    *,
    outermost: bool,
    quantile: float = PROFILE_QUANTILE,
) -> Optional[_FittedCircle]:
    """Fit a circle to one radial edge, taken over every ray.

    With `outermost`, the radius sought is the last one whose median edge
    strength still reaches `RIM_STRENGTH_FRACTION` of the peak — the outer glass
    rim. Without it, the strongest radius is taken instead, which is whichever
    concentric structure is sharpest and is used only to place the centre.
    """
    radii, samples = _radial_samples(plane, centre_y, centre_x, search_from, search_to)
    derivative = np.abs(np.gradient(samples, axis=0))
    profile = np.nanpercentile(derivative, quantile, axis=1)
    peak = float(np.nanmax(profile)) if np.any(np.isfinite(profile)) else 0.0
    if not np.isfinite(peak) or peak < MIN_PROFILE_EDGE:
        return None

    strong = np.nonzero(profile >= RIM_STRENGTH_FRACTION * peak)[0]
    if strong.size == 0:
        return None
    seed_radius = float(radii[strong[-1] if outermost else int(np.argmax(profile))])

    band = np.abs(radii - seed_radius) <= RIM_REFINE_BAND * seed_radius
    banded_radii = radii[band]
    # A ray that leaves the frame samples NaN; -inf keeps it out of the maximum
    # without turning the whole column into NaN.
    banded = np.where(np.isnan(derivative[band]), -np.inf, derivative[band])
    strength = banded.max(axis=0)
    found = strength >= RAY_STRENGTH_FRACTION * peak
    coverage = float(found.mean())
    if found.sum() < 3:
        return None

    angles = np.linspace(0.0, 2.0 * np.pi, RAY_COUNT, endpoint=False)[found]
    per_ray = banded_radii[banded.argmax(axis=0)][found]
    ys = centre_y + per_ray * np.sin(angles)
    xs = centre_x + per_ray * np.cos(angles)
    fitted_y, fitted_x, fitted_radius = _fit_circle(ys, xs)
    residual = np.hypot(ys - fitted_y, xs - fitted_x) - fitted_radius
    dispersion = float(np.median(np.abs(residual)) / fitted_radius)
    return _FittedCircle(
        centre_y=fitted_y,
        centre_x=fitted_x,
        radius=fitted_radius,
        dispersion=dispersion,
        coverage=coverage,
    )


def _diagnose(
    plane: np.ndarray,
    centre_y: float,
    centre_x: float,
    search_from: float,
    search_to: float,
) -> ScaleReading:
    """Name why no circle was measured, without ever producing a scale."""
    partial = _fit_edge(
        plane,
        centre_y,
        centre_x,
        search_from,
        search_to,
        outermost=True,
        quantile=DIAGNOSTIC_QUANTILE,
    )
    if partial is None:
        return _refused(ScaleRefusal.NO_CIRCLE_FOUND)
    return _refused(
        ScaleRefusal.INCONSISTENT_RIM,
        rim_dispersion=partial.dispersion,
        ray_coverage=partial.coverage,
    )


def _fit_circle(ys: np.ndarray, xs: np.ndarray) -> tuple[float, float, float]:
    """Least-squares circle through the points, by the algebraic (Kåsa) fit.

    Linear in the unknowns, so it has one solution and no starting guess. Its
    known bias toward small radii on a short arc does not reach here, where the
    points cover the whole circumference.
    """
    design = np.column_stack([2.0 * xs, 2.0 * ys, np.ones_like(xs)])
    target = xs**2 + ys**2
    solution, *_ = np.linalg.lstsq(design, target, rcond=None)
    centre_x, centre_y, offset = solution
    radius = float(np.sqrt(max(offset + centre_x**2 + centre_y**2, 0.0)))
    return float(centre_y), float(centre_x), radius


def _farthest_corner(plane: np.ndarray, centre_y: float, centre_x: float) -> float:
    """Return the distance from the centre to the farthest frame corner.

    The search band is bounded by the frame's reach rather than by the largest
    circle that fits inside it. A dish photographed close fills the shorter
    side, and stopping at the nearest edge would end the search before the
    profile falls away from the rim — which reads as a rim at the band's edge
    rather than as the rim.
    """
    height, width = plane.shape
    return max(
        float(np.hypot(centre_y - corner_y, centre_x - corner_x))
        for corner_y in (0.0, float(height - 1))
        for corner_x in (0.0, float(width - 1))
    )


def _distribution(readings: Sequence[float]) -> ScaleDistribution:
    if not readings:
        return ScaleDistribution(
            count=0, minimum=None, p5=None, p50=None, p95=None, maximum=None
        )
    values = np.asarray(readings, dtype=np.float64)
    quantiles = np.percentile(values, [0.0, 5.0, 50.0, 95.0, 100.0])
    return ScaleDistribution(
        count=len(readings),
        minimum=float(quantiles[0]),
        p5=float(quantiles[1]),
        p50=float(quantiles[2]),
        p95=float(quantiles[3]),
        maximum=float(quantiles[4]),
    )


def _refused(
    cause: ScaleRefusal, *, rim_dispersion: float = 0.0, ray_coverage: float = 0.0
) -> ScaleReading:
    return ScaleReading(
        mm_per_px=None,
        disc_diameter_px=None,
        centre_x_px=None,
        centre_y_px=None,
        rim_dispersion=rim_dispersion,
        ray_coverage=ray_coverage,
        refusal=cause,
    )
