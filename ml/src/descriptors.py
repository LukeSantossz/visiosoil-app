"""Classical texture descriptors over one greyscale patch (SPEC 0054).

The descriptor arm of the E0 gate does not look at a photograph and does not
look at a patch's pixels either. It looks at these numbers: four component
groups measuring intensity, spatial frequency, local micro-texture and
second-order spatial statistics over a single patch of
[ADR 0018](../../docs/adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md).

**The patch is scale-normalised before it reaches here, and that is what makes
the spectral group mean anything.** `src.patches` resamples every photograph to
one canonical millimetres per pixel and then cuts a fixed physical area of soil,
so a cycle across the patch is the same physical wavelength in every photograph
of the archive. Without it a band would mix a grain in one photograph with a
clod in another, and the group would measure how far away the camera stood.

The groups are also the units of the ablation SPEC 0044 requires, which is why
`describe_patch` takes a set of them and why their widths are published as data:
an arm run without one group must differ from the full arm by exactly that
group's features and by nothing else.

`scikit-image` is deliberately not a dependency (SPEC 0054, on the precedent
SPEC 0052 set for OpenCV). The LBP and the GLCM are a few dozen lines of numpy
each, and they are tested against hand-computed values on small arrays rather
than against another library, so the tests do not inherit a second
implementation's conventions along with its answers.

Everything here is pure arithmetic over pixels: no model, no TensorFlow, no
randomness and no seed.
"""

from __future__ import annotations

from functools import lru_cache
from types import MappingProxyType
from typing import Callable, Mapping, Sequence, Tuple

import numpy as np

# --- fixed points of the descriptors ----------------------------------------
# These are not tunable hyper-parameters. SPEC 0054 fixes the component groups
# before the run precisely so the gate cannot select among them, so changing one
# changes what the arm measures and moves every figure it has ever reported.

#: Grey levels the co-occurrence matrix is built over. Sixteen, not 256: a
#: 256-level matrix has 65,536 cells and a 160 px patch supplies about 25,000
#: pairs per direction, so almost every cell would be zero or one and the
#: second-order statistics would be estimating sampling noise. At 16 levels the
#: matrix has 256 cells and roughly a hundred pairs each.
GLCM_LEVELS = 16
#: Quantisation is over the fixed 0-255 range and never over the patch's own
#: minimum and maximum. A per-patch rescale would make a flat patch and a
#: contrasty one produce the same matrix, and contrast is the first thing the
#: group reports.
GLCM_BIN_WIDTH = 256 // GLCM_LEVELS
#: 0, 45, 90 and 135 degrees at one step, as ``(dy, dx)`` with rows increasing
#: downward. Four directions because the dish is placed at an arbitrary angle:
#: averaging over them is what makes the group say something about the soil
#: rather than about how the sample was set down.
GLCM_OFFSETS: Tuple[Tuple[int, int], ...] = ((0, 1), (-1, 1), (-1, 0), (-1, -1))

#: Neighbours compared with the centre, anticlockwise from east. At P = 8 and
#: R = 1 the ring is exactly the eight pixels touching the centre, so the code
#: is read off the image and no interpolation stands between the definition and
#: the arithmetic. The starting point and the direction are free: the
#: rotation-invariant mapping depends only on the circular order.
LBP_NEIGHBOURS: Tuple[Tuple[int, int], ...] = (
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
)
LBP_POINTS = len(LBP_NEIGHBOURS)
#: One bin per number of ones a uniform code can carry, and one for everything
#: else — the rotation-invariant uniform mapping of Ojala et al.
LBP_BINS = LBP_POINTS + 2

#: Radial spatial-frequency bands, log-spaced. A natural image's power falls
#: about as the square of the frequency, so log-spaced bands carry comparable
#: energy each where equal-width bands would put nearly all of it in the lowest
#: one; and particle-size classes are themselves spaced by factors rather than
#: by steps, so a band is a roughly constant relative range of grain size.
SPECTRAL_BANDS = 8
#: The lowest band starts here, in cycles across the patch. One cycle across a
#: 21 mm patch is a lighting gradient over the dish, not a grain, and a band
#: holding it would let the arm score the lamp. The zero-frequency coefficient
#: — the patch's total brightness — is below this and so is excluded with it.
MIN_CYCLES_PER_PATCH = 2.0

#: A 3x3 neighbourhood needs one, and every group is undefined below it: no
#: interior pixel to read an LBP code from, no pair to fill a co-occurrence
#: matrix. Refused rather than padded, on `image_quality.laplacian_variance`'s
#: precedent — an invented border is a measurement of the padding. The spectral
#: group's floor is higher and its own: a patch has to reach
#: `MIN_CYCLES_PER_PATCH` before it has a band, and `_band_map` refuses it by
#: name below that.
MIN_SIDE_PX = 3


#: Every feature this module computes, by group and in output order. The name
#: carries its group before the dot, so an ablation report can attribute a
#: number without holding a second table.
_GROUP_FEATURES: Mapping[str, Tuple[str, ...]] = {
    "first_order": (
        "first_order.mean",
        "first_order.std",
        "first_order.skewness",
        "first_order.kurtosis",
    ),
    "spectral": tuple(f"spectral.band_{band}" for band in range(SPECTRAL_BANDS)),
    "lbp": tuple(f"lbp.uniform_{ones}" for ones in range(LBP_POINTS + 1))
    + ("lbp.non_uniform",),
    "glcm": (
        "glcm.contrast",
        "glcm.homogeneity",
        "glcm.energy",
        "glcm.correlation",
    ),
}

#: The component groups, in the order `describe_patch` writes them.
GROUPS: Tuple[str, ...] = tuple(_GROUP_FEATURES)

#: How many features each group contributes. Published so an ablation can state
#: the width it expects instead of a caller carrying the count in its head.
GROUP_WIDTHS: Mapping[str, int] = MappingProxyType(
    {group: len(features) for group, features in _GROUP_FEATURES.items()}
)


def feature_names(groups: Sequence[str] = GROUPS) -> Tuple[str, ...]:
    """Name every number `describe_patch` returns for `groups`, in its order."""
    return tuple(
        name for group in _selected(groups) for name in _GROUP_FEATURES[group]
    )


def describe_patch(
    patch: np.ndarray, groups: Sequence[str] = GROUPS
) -> np.ndarray:
    """Describe one greyscale patch as a 1-D vector of `groups`' features.

    `patch` is what `patches.cut_patches` produces: a ``uint8`` array, either
    ``(side, side)`` or ``(side, side, 3)`` whose three channels are identical.

    The output is always in :data:`GROUPS` order whatever order `groups` lists,
    so two callers that asked for the same set get the same vector — which is
    what lets an ablation compare its result with a slice of the full one.

    Raises:
        ValueError: If `groups` names something this module does not compute or
            is empty, or if `patch` is not a greyscale ``uint8`` patch of at
            least :data:`MIN_SIDE_PX` a side.
    """
    selected = _selected(groups)
    plane = _grey_plane(patch)
    return np.concatenate([_COMPUTE[group](plane) for group in selected])


# --- the groups, one at a time ----------------------------------------------


def _first_order(plane: np.ndarray) -> np.ndarray:
    """Mean, standard deviation, skewness and excess kurtosis of intensity.

    The control within the arm: an arm that wins on this group alone learned how
    bright the photograph was, not what the soil looks like. Values are the
    patch's own 0-255 grey levels — the arm standardises every feature before
    the classifier sees it, so there is nothing to gain from rescaling here.
    """
    values = plane.astype(np.float64)
    mean = float(values.mean())
    centred = values - mean
    # The squared deviations, once, for all three moments that follow. Written
    # as a product rather than `centred ** 3` and `centred ** 4` because numpy
    # sends an integer power above two through `pow()` once per element, which
    # costs more than the other three groups put together.
    squared = centred * centred
    deviation = float(np.sqrt(squared.mean()))
    if deviation <= 0.0:
        # A patch of one grey level has no shape to report. Zero is the neutral
        # value of both moments — no asymmetry, no excess over a Gaussian — and,
        # unlike the 0/0 the definitions give, it is a number. A NaN here
        # standardises into a NaN for every row of the fold.
        return np.array([mean, 0.0, 0.0, 0.0])
    skewness = float((squared * centred).mean()) / deviation**3
    kurtosis = float((squared * squared).mean()) / deviation**4 - 3.0
    return np.array([mean, deviation, skewness, kurtosis])


def _spectral(plane: np.ndarray) -> np.ndarray:
    """Energy per radial frequency band, as a distribution over the bands.

    Normalised by the banded total, so the group says **where** the energy sits
    and not how much light there was: doubling the contrast multiplies every
    band by the same square and cancels, and adding a constant moves only the
    zero-frequency coefficient, which no band holds.
    """
    energy = _radial_band_energy(plane)
    total = float(energy.sum())
    if total <= 0.0:
        # A patch with no structure has no distribution over bands. Zeros says
        # that; a uniform vector would claim equal energy in every band, which
        # is not what was measured.
        return np.zeros(SPECTRAL_BANDS)
    return energy / total


def _radial_band_energy(plane: np.ndarray) -> np.ndarray:
    """Unnormalised power summed over each radial frequency band."""
    positions, bands = _band_map(*plane.shape)
    spectrum = np.fft.fft2(plane.astype(np.float64))
    # The squared modulus, without the square root `abs` would take and then
    # square away again.
    power = (spectrum.real**2 + spectrum.imag**2).ravel()[positions]
    return np.bincount(bands, weights=power, minlength=SPECTRAL_BANDS)


@lru_cache(maxsize=8)
def _band_map(height: int, width: int) -> Tuple[np.ndarray, np.ndarray]:
    """Which frequency bins fall in which band, for one patch size.

    Cached: the arm calls `describe_patch` once per patch, twenty-five patches
    to the photograph, and the map depends on nothing but the shape.

    Raises:
        ValueError: If the patch is too small to reach the lowest band.
    """
    nyquist = min(height, width) / 2.0
    if nyquist <= MIN_CYCLES_PER_PATCH:
        raise ValueError(
            f"a {height}x{width} px patch resolves {nyquist:g} cycles across "
            f"itself and the lowest spectral band starts at "
            f"{MIN_CYCLES_PER_PATCH:g}; there is no band to measure"
        )

    edges = np.geomspace(MIN_CYCLES_PER_PATCH, nyquist, SPECTRAL_BANDS + 1)
    # Frequencies as cycles across the patch, which is a physical wavelength
    # because the patch is a fixed physical size.
    frequency_y = np.fft.fftfreq(height) * height
    frequency_x = np.fft.fftfreq(width) * width
    radius = np.hypot(frequency_y[:, None], frequency_x[None, :])

    band = np.searchsorted(edges, radius, side="right") - 1
    # `searchsorted` puts the Nyquist radius itself one band past the last. The
    # top band's upper edge is closed and it belongs there.
    band = np.where(radius == edges[-1], SPECTRAL_BANDS - 1, band)
    # Everything below the first edge — the zero-frequency coefficient — and
    # everything past the Nyquist radius, where only the corner directions of
    # the grid are represented and a band would measure direction as much as
    # frequency.
    selected = (band >= 0) & (band < SPECTRAL_BANDS)

    positions = np.flatnonzero(selected)
    bands = band[selected].astype(np.intp)
    positions.flags.writeable = False
    bands.flags.writeable = False
    return positions, bands


def _lbp(plane: np.ndarray) -> np.ndarray:
    """Rotation-invariant uniform local binary pattern histogram, P = 8, R = 1.

    A neighbour scores one when it is **at least** the centre, so a tie counts
    as a rise and a flat patch codes as all ones rather than falling into the
    non-uniform bin. Interior pixels only, so no invented border contributes.

    The histogram is a distribution over the P + 2 codes, which is what makes it
    comparable between patches and what makes it survive any transform that
    preserves the order of the intensities — the property SPEC 0054 wants it for,
    since the archive's capture populations differ in lighting.
    """
    height, width = plane.shape
    centre = plane[1:-1, 1:-1]
    code = np.zeros(centre.shape, dtype=np.intp)
    for bit, (dy, dx) in enumerate(LBP_NEIGHBOURS):
        neighbour = plane[1 + dy : height - 1 + dy, 1 + dx : width - 1 + dx]
        code |= (neighbour >= centre).astype(np.intp) << bit

    bins = _lbp_bin_of_code()[code]
    return np.bincount(bins.ravel(), minlength=LBP_BINS) / bins.size


@lru_cache(maxsize=1)
def _lbp_bin_of_code() -> np.ndarray:
    """The rotation-invariant uniform mapping, as a lookup over all 256 codes.

    A code with at most two circular 0/1 transitions is *uniform*: every
    rotation of the patch is a circular shift of its bits, and both the
    transition count and the number of ones survive a shift, so the number of
    ones names it. Everything else lands in one bin: the non-uniform codes are
    individually rare and collectively noise at this patch size.
    """
    table = np.empty(1 << LBP_POINTS, dtype=np.intp)
    for code in range(1 << LBP_POINTS):
        bits = [(code >> position) & 1 for position in range(LBP_POINTS)]
        transitions = sum(
            bits[position] != bits[(position + 1) % LBP_POINTS]
            for position in range(LBP_POINTS)
        )
        table[code] = sum(bits) if transitions <= 2 else LBP_BINS - 1
    return table


def _glcm(plane: np.ndarray) -> np.ndarray:
    """Contrast, homogeneity, energy and correlation, averaged over directions.

    The four figures are computed per direction and then averaged, which is the
    classical Haralick reading: each is the mean of four well-defined
    quantities rather than a statistic of a matrix no single direction produced.
    """
    levels = plane // GLCM_BIN_WIDTH
    total = np.zeros(len(_GROUP_FEATURES["glcm"]))
    for offset in GLCM_OFFSETS:
        total += _glcm_features(_cooccurrence(levels, offset))
    return total / len(GLCM_OFFSETS)


def _cooccurrence(levels: np.ndarray, offset: Tuple[int, int]) -> np.ndarray:
    """Symmetric counts of the level pairs one `offset` apart.

    Symmetric because the pair is unordered: which of the two pixels is "first"
    is the sign of the offset and not a property of the texture. It is also what
    makes the four directions a set that a quarter turn permutes among itself,
    so their average is rotation-invariant exactly rather than nearly.
    """
    dy, dx = offset
    rows = slice(max(0, -dy), levels.shape[0] - max(0, dy))
    columns = slice(max(0, -dx), levels.shape[1] - max(0, dx))
    first = levels[rows, columns]
    second = levels[
        rows.start + dy : rows.stop + dy, columns.start + dx : columns.stop + dx
    ]

    pair = first.ravel().astype(np.intp) * GLCM_LEVELS + second.ravel()
    counts = np.bincount(pair, minlength=GLCM_LEVELS**2).reshape(
        GLCM_LEVELS, GLCM_LEVELS
    )
    return counts + counts.T


def _glcm_features(matrix: np.ndarray) -> np.ndarray:
    """The four Haralick figures of one co-occurrence matrix.

    ``energy`` is the angular second moment, the sum of the squared
    probabilities; some libraries report its square root under the same name, so
    the definition is written down here rather than assumed.
    """
    index, squared_difference, inverse_difference = _level_grid()
    probability = matrix / float(matrix.sum())

    contrast = float((probability * squared_difference).sum())
    homogeneity = float((probability * inverse_difference).sum())
    energy = float((probability * probability).sum())

    marginal = probability.sum(axis=1)
    mean = float((marginal * index).sum())
    variance = float((marginal * (index - mean) ** 2).sum())
    if variance <= 0.0:
        # One grey level, so every pair is identical and the ratio is 0/0. A
        # patch whose every step leaves the level unchanged is perfectly
        # correlated, and that is the value the limit approaches from every
        # side; a NaN would poison the whole fold.
        correlation = 1.0
    else:
        deviation = index - mean
        # The matrix is symmetric, so the row and column marginals are the same
        # distribution and the denominator is one variance rather than two
        # standard deviations that happen to be equal.
        correlation = float(
            (probability * deviation[:, None] * deviation[None, :]).sum() / variance
        )
    return np.array([contrast, homogeneity, energy, correlation])


@lru_cache(maxsize=1)
def _level_grid() -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """The level index and the two difference kernels the features weigh by."""
    index = np.arange(GLCM_LEVELS, dtype=np.float64)
    difference = index[:, None] - index[None, :]
    squared = difference**2
    for array in (index, squared):
        array.flags.writeable = False
    inverse = 1.0 / (1.0 + squared)
    inverse.flags.writeable = False
    return index, squared, inverse


# --- what a caller may pass -------------------------------------------------


_COMPUTE: Mapping[str, Callable[[np.ndarray], np.ndarray]] = {
    "first_order": _first_order,
    "spectral": _spectral,
    "lbp": _lbp,
    "glcm": _glcm,
}


def _selected(groups: Sequence[str]) -> Tuple[str, ...]:
    """The requested groups in module order, or a refusal naming what was not.

    Raises:
        ValueError: If a name is not a component group, or if none were asked
            for. Both are a caller's mistake that would otherwise return a
            plausible vector of the wrong width.
    """
    requested = set(groups)
    unknown = sorted(requested - set(GROUPS))
    if unknown:
        raise ValueError(
            f"no such descriptor group(s): {', '.join(unknown)}; this module "
            f"computes {', '.join(GROUPS)}"
        )
    if not requested:
        raise ValueError(
            "a descriptor of no component groups describes nothing; ask for "
            f"one or more of {', '.join(GROUPS)}"
        )
    return tuple(group for group in GROUPS if group in requested)


def _grey_plane(patch: np.ndarray) -> np.ndarray:
    """The single greyscale plane of a patch, or a refusal naming why not.

    Raises:
        ValueError: If the patch is not ``uint8``, is not greyscale, or is
            smaller than :data:`MIN_SIDE_PX` a side. A colour patch read through
            its red channel and a float patch quantised as though it were bytes
            would each be answered with a number, and nothing downstream can
            tell a wrong descriptor from a right one.
    """
    array = np.asarray(patch)
    if array.dtype != np.uint8:
        raise ValueError(
            f"a patch is uint8 grey levels, as `patches.cut_patches` cuts them; "
            f"got {array.dtype}"
        )

    if array.ndim == 2:
        plane = array
    elif array.ndim == 3 and array.shape[2] == 3:
        plane = array[:, :, 0]
        if not (
            np.array_equal(plane, array[:, :, 1])
            and np.array_equal(plane, array[:, :, 2])
        ):
            raise ValueError(
                "a patch's three channels are not identical, so this is a "
                "colour image and not the greyscale `patches.cut_patches` "
                "replicates; describing its first channel would describe red"
            )
    else:
        raise ValueError(
            f"a patch is (side, side) or (side, side, 3); got shape {array.shape}"
        )

    if min(plane.shape) < MIN_SIDE_PX:
        raise ValueError(
            f"a patch of {plane.shape[0]}x{plane.shape[1]} px has no interior "
            f"pixel and no pair to describe; the floor is {MIN_SIDE_PX} a side"
        )
    return plane
