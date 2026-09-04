"""Acceptance criteria for the classical texture descriptors (SPEC 0054).

Every acceptance criterion about the descriptors in
`docs/specs/0054-the-two-e0-arms-that-do-not-exist-yet.md` has a test of its
name here. The rest guard what a descriptor can get wrong without anything
downstream noticing: a definition nobody wrote down, a division by a variance
that is zero, and a patch that is not what it was taken for.

The LBP and the GLCM are asserted against values computed **by hand** on arrays
small enough to enumerate, never against another library's output. SPEC 0054
names the reason: a hand-rolled implementation that agrees with an expectation
derived from the same misreading is the failure mode, and a second library would
not catch it — it would only substitute its conventions for ours. The working
for every expected value is written out beside the value it produces.

Everything here runs on arrays. The descriptors are arithmetic over pixels, so
they need no dataset, no image file and no TensorFlow.
"""

import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

from src.descriptors import (
    GLCM_LEVELS,
    GLCM_OFFSETS,
    GROUP_WIDTHS,
    GROUPS,
    LBP_BINS,
    SPECTRAL_BANDS,
    _cooccurrence,
    _radial_band_energy,
    describe_patch,
    feature_names,
)

ML_ROOT = Path(__file__).resolve().parents[1]


def _textured(side: int = 32) -> np.ndarray:
    """A patch with structure at several frequencies and no symmetry.

    Values sit in [112, 144] so that doubling the contrast about 128 lands back
    inside [0, 255] on exact integers: the spectral arithmetic is then testable
    without a clip or a rounding step standing between the two patches.
    """
    rows, columns = np.mgrid[0:side, 0:side]
    return (128 + (rows * 7 + columns * 13) % 33 - 16).astype(np.uint8)


def _even_valued(side: int = 32) -> np.ndarray:
    """A patch whose values are all even, so ``v // 2`` preserves their order.

    Monotonic-intensity invariance is invariance under a transform that
    preserves the *order* of the values present. ``v // 2`` collides odd with
    even, and a collision creates an equality the descriptor is right to see, so
    the fixture avoids one rather than the test tolerating it.
    """
    rows, columns = np.mgrid[0:side, 0:side]
    return (2 * ((rows * 5 + columns * 3) % 128)).astype(np.uint8)


def _band_of(name: str, vector: np.ndarray) -> np.ndarray:
    """The slice of a full descriptor `vector` belonging to group `name`."""
    start = 0
    for group in GROUPS:
        if group == name:
            return vector[start : start + GROUP_WIDTHS[group]]
        start += GROUP_WIDTHS[group]
    raise AssertionError(f"{name} is not among {GROUPS}")


# --- hand-computed values ---------------------------------------------------


def test_lbp_and_glcm_match_hand_computed_values():
    """Both, on arrays whose every pair and every neighbourhood is enumerated.

    **LBP.** P = 8 at R = 1 is the eight pixels touching the centre, so no
    interpolation stands between the definition and the arithmetic. A neighbour
    scores 1 when it is **at least** the centre. The code is read anticlockwise
    from east; the rotation-invariant uniform mapping counts the circular 0/1
    transitions, and a code with at most two of them is filed under its number
    of ones, everything else under the last bin.

    A 3x3 has exactly one interior pixel, so its histogram is that pixel's bin.

        [[200, 200, 200],      centre 100; E=10 NE=200 N=200 NW=200
         [ 10, 100,  10],      W=10 SW=10 S=10 SE=10  ->  0 1 1 1 0 0 0 0
         [ 10,  10,  10]]      two transitions, three ones  ->  bin 3

        [[200,  10, 200],      centre 100; the four corners are above it and
         [ 10, 100,  10],      the four edges below  ->  0 1 0 1 0 1 0 1
         [200,  10, 200]]      eight transitions  ->  the non-uniform bin

    A 4x4 has four interior pixels and exercises the tie rule:

        [[  0,   0,   0,   0]     (1,1)=50 : E=200 S=200 SE=50 are >= 50
         [  0,  50, 200,   0]              -> 1 0 0 0 0 0 1 1, two transitions,
         [  0, 200,  50,   0]                 three ones -> bin 3
         [  0,   0,   0,   0]]     (2,2)=50 : N=200 NW=50 W=200 -> bin 3
                                   (1,2)=200: only SW=200 ties  -> bin 1
                                   (2,1)=200: only NE=200 ties  -> bin 1

    so the histogram is half in bin 1 and half in bin 3.

    **GLCM.** Grey is quantised to 16 levels, so a value of 16k has level k.
    Each direction counts the ordered pairs one step apart and adds the
    transpose, which is what makes the pair unordered. On

        [[ 0,  0, 32],        levels  [[0, 0, 2],
         [ 0, 32,  0],                 [0, 2, 0],
         [32,  0,  0]]                 [2, 0, 0]]

    the horizontal step gives the ordered pairs (0,0), (0,2) / (0,2), (2,0) /
    (2,0), (0,0), so the symmetric counts are 4 at (0,0), (0,2) and (2,0) and
    the twelve pairs normalise to a third each:

        contrast    = 2 * (1/3) * 4                  = 8/3
        homogeneity = 1/3 + 2 * (1/3) / 5            = 7/15
        energy      = 3 * (1/3)^2                    = 1/3
        marginals   = (2/3 at level 0, 1/3 at 2), mean 2/3, variance 8/9
        correlation = (-4/9) / (8/9)                 = -1/2

    The vertical step gives the same three counts, so it repeats those figures.
    The 45-degree step runs **along** the anti-diagonal and never changes level:
    counts 4 at (0,0) and 4 at (2,2), giving contrast 0, homogeneity 1, energy
    1/2 and correlation 1. The 135-degree step crosses it: counts 4 at (0,0) and
    2 at each of (0,2) and (2,0), giving contrast 2, homogeneity 0.6, energy 3/8
    and correlation -1/3. Averaged over the four directions:

        contrast    = (8/3 + 8/3 + 0 + 2) / 4        = 11/6
        homogeneity = (7/15 + 7/15 + 1 + 3/5) / 4    = 19/30
        energy      = (1/3 + 1/3 + 1/2 + 3/8) / 4    = 37/96
        correlation = (-1/2 - 1/2 + 1 - 1/3) / 4     = -1/12

    The second array is three horizontal bands of levels 0, 1 and 3. The
    horizontal step never leaves a band, so it scores contrast 0, homogeneity 1,
    energy 1/3 and correlation 1; the other three all pair level 0 with 1 and 1
    with 3, four counts each way, scoring contrast 5/2, homogeneity 7/20, energy
    1/4 and correlation -1/19. It is the array that would catch a reader whose
    rows and columns are the wrong way round.
    """
    single_corner = np.array(
        [[200, 200, 200], [10, 100, 10], [10, 10, 10]], dtype=np.uint8
    )
    histogram = describe_patch(single_corner, groups=["lbp"])
    expected = np.zeros(LBP_BINS)
    expected[3] = 1.0
    assert histogram == pytest.approx(expected, abs=1e-12)

    checkerboard = np.array(
        [[200, 10, 200], [10, 100, 10], [200, 10, 200]], dtype=np.uint8
    )
    histogram = describe_patch(checkerboard, groups=["lbp"])
    expected = np.zeros(LBP_BINS)
    expected[LBP_BINS - 1] = 1.0
    assert histogram == pytest.approx(expected, abs=1e-12)

    diagonal_pair = np.array(
        [
            [0, 0, 0, 0],
            [0, 50, 200, 0],
            [0, 200, 50, 0],
            [0, 0, 0, 0],
        ],
        dtype=np.uint8,
    )
    histogram = describe_patch(diagonal_pair, groups=["lbp"])
    expected = np.zeros(LBP_BINS)
    expected[1] = 0.5
    expected[3] = 0.5
    assert histogram == pytest.approx(expected, abs=1e-12)

    anti_diagonal = np.array(
        [[0, 0, 32], [0, 32, 0], [32, 0, 0]], dtype=np.uint8
    )
    levels = anti_diagonal // (256 // GLCM_LEVELS)

    horizontal = np.zeros((GLCM_LEVELS, GLCM_LEVELS), dtype=np.int64)
    horizontal[0, 0] = 4
    horizontal[0, 2] = 4
    horizontal[2, 0] = 4
    assert np.array_equal(_cooccurrence(levels, GLCM_OFFSETS[0]), horizontal)

    up_right = np.zeros((GLCM_LEVELS, GLCM_LEVELS), dtype=np.int64)
    up_right[0, 0] = 4
    up_right[2, 2] = 4
    assert np.array_equal(_cooccurrence(levels, GLCM_OFFSETS[1]), up_right)

    # The vertical step reads the same three counts as the horizontal one on an
    # array that is its own transpose.
    assert np.array_equal(_cooccurrence(levels, GLCM_OFFSETS[2]), horizontal)

    up_left = np.zeros((GLCM_LEVELS, GLCM_LEVELS), dtype=np.int64)
    up_left[0, 0] = 4
    up_left[0, 2] = 2
    up_left[2, 0] = 2
    assert np.array_equal(_cooccurrence(levels, GLCM_OFFSETS[3]), up_left)

    assert describe_patch(anti_diagonal, groups=["glcm"]) == pytest.approx(
        np.array([11.0 / 6.0, 19.0 / 30.0, 37.0 / 96.0, -1.0 / 12.0]), abs=1e-12
    )

    bands = np.array(
        [[0, 0, 0], [16, 16, 16], [48, 48, 48]], dtype=np.uint8
    )
    assert describe_patch(bands, groups=["glcm"]) == pytest.approx(
        np.array(
            [
                (0.0 + 2.5 * 3) / 4.0,
                (1.0 + 0.35 * 3) / 4.0,
                (1.0 / 3.0 + 0.25 * 3) / 4.0,
                (1.0 - 3.0 / 19.0) / 4.0,
            ]
        ),
        abs=1e-12,
    )


def test_the_intensity_moments_are_the_hand_computed_ones():
    """Nine values, eight of them zero, so every moment is done in the head.

    The mean of eight zeros and a nine is 1, and the deviations are eight of -1
    and one of 8. The population variance is (8 + 64) / 9 = 8, so the standard
    deviation is 2 root 2. The third moment is (-8 + 512) / 9 = 56 and the
    fourth is (8 + 4096) / 9 = 456, so

        skewness = 56 / (2 root 2)^3 = 7 root 2 / 4
        kurtosis = 456 / (2 root 2)^4 - 3 = 456 / 64 - 3 = 4.125

    which pins two conventions the vector would otherwise carry unstated: the
    skew is positive because the single bright pixel is a right tail, and the
    kurtosis is the **excess** over a Gaussian rather than the raw 7.125.
    """
    single_bright = np.array([[0, 0, 0], [0, 0, 0], [0, 0, 9]], dtype=np.uint8)

    assert describe_patch(single_bright, groups=["first_order"]) == pytest.approx(
        np.array([1.0, 2.0 * np.sqrt(2.0), 7.0 * np.sqrt(2.0) / 4.0, 4.125]),
        abs=1e-12,
    )


# --- what the groups claim about themselves ---------------------------------


def test_descriptors_are_invariant_to_what_they_claim_to_be():
    """The LBP survives a monotonic intensity change; the whole vector a turn.

    The LBP compares each neighbour with its centre and nothing else, so any
    transform that preserves the order of the values leaves every code alone.
    ``v -> v // 2 + 100`` is one on the even values the fixture carries, and it
    moves every pixel, which is what makes the assertion mean something.

    The dish sits at an arbitrary angle in the frame, so a quarter turn must
    change nothing. It does not, and exactly rather than nearly: the interior
    pixels map onto the interior pixels and each LBP code is a circular shift of
    itself; the four GLCM offsets are permuted among themselves once the pair is
    unordered, so their average is the same four numbers in a different order;
    the power spectrum turns with the patch and the bands are annuli about the
    origin; and the intensity moments read the same multiset of values.
    """
    patch = _even_valued()
    lightened = np.clip(patch.astype(np.int64) // 2 + 100, 0, 255).astype(np.uint8)

    assert not np.array_equal(patch, lightened), "the transform must move pixels"
    assert np.array_equal(
        describe_patch(patch, groups=["lbp"]),
        describe_patch(lightened, groups=["lbp"]),
    )

    textured = _textured()
    turned = np.rot90(textured)

    assert not np.array_equal(textured, turned), "the turn must move pixels"
    assert describe_patch(turned, groups=["glcm"]) == pytest.approx(
        describe_patch(textured, groups=["glcm"]), abs=1e-12
    )
    assert describe_patch(turned) == pytest.approx(
        describe_patch(textured), rel=1e-9, abs=1e-12
    )


def test_the_spectral_bands_scale_as_the_arithmetic_says():
    """Contrast multiplies every band by its square; a constant moves only DC.

    The transform is linear, so scaling the contrast about the mean by `a`
    scales every Fourier coefficient by `a` and every band's energy by `a^2`.
    The reported vector is those energies over their sum, so the square cancels
    and the distribution is unchanged — which is the point of normalising: the
    group is meant to say where the energy sits, not how much light there was.

    Adding a constant adds to the zero-frequency coefficient alone, and that
    coefficient is excluded, so it changes nothing at all.
    """
    patch = _textured()
    doubled = (128 + 2 * (patch.astype(np.int64) - 128)).astype(np.uint8)
    brighter = np.clip(patch.astype(np.int64) + 20, 0, 255).astype(np.uint8)

    bands = describe_patch(patch, groups=["spectral"])
    assert np.count_nonzero(bands) >= 2, "a one-band patch would pass vacuously"
    assert bands.sum() == pytest.approx(1.0, abs=1e-12)

    assert _radial_band_energy(doubled) == pytest.approx(
        4.0 * _radial_band_energy(patch), rel=1e-9
    )
    assert describe_patch(doubled, groups=["spectral"]) == pytest.approx(
        bands, rel=1e-9, abs=1e-12
    )
    assert describe_patch(brighter, groups=["spectral"]) == pytest.approx(
        bands, rel=1e-9, abs=1e-12
    )


# --- the ablation -----------------------------------------------------------


def test_an_ablation_removes_one_component_group_at_a_time():
    """Dropping a group shortens the vector by that group's width, and no more.

    SPEC 0044 asks the arm to be run with each group removed, so the removal has
    to be exactly a removal: every number the shortened vector carries is the
    number the full vector carried, unchanged, or the ablation would confound
    "this group carries the signal" with "the other groups moved".
    """
    patch = _textured()
    full = describe_patch(patch)

    assert len(full) == sum(GROUP_WIDTHS.values())
    assert set(GROUP_WIDTHS) == set(GROUPS)

    for removed in GROUPS:
        kept = [group for group in GROUPS if group != removed]
        ablated = describe_patch(patch, groups=kept)

        assert len(ablated) == len(full) - GROUP_WIDTHS[removed]
        assert np.array_equal(
            ablated,
            np.concatenate([_band_of(group, full) for group in kept]),
        )
        assert feature_names(kept) == tuple(
            name
            for name in feature_names()
            if not name.startswith(f"{removed}.")
        )

    # The order is the module's, not the caller's, so two callers that asked for
    # the same groups get the same vector and the same names.
    assert np.array_equal(
        describe_patch(patch, groups=["glcm", "first_order"]),
        describe_patch(patch, groups=["first_order", "glcm"]),
    )

    with pytest.raises(ValueError, match="haralick"):
        describe_patch(patch, groups=["first_order", "haralick"])
    with pytest.raises(ValueError):
        describe_patch(patch, groups=[])


def test_the_feature_names_name_every_number_in_order():
    """A caller writing an ablation report must be able to say what went."""
    patch = _textured()
    names = feature_names()

    assert len(names) == len(describe_patch(patch))
    assert len(set(names)) == len(names)

    start = 0
    for group in GROUPS:
        width = GROUP_WIDTHS[group]
        assert all(
            name.startswith(f"{group}.") for name in names[start : start + width]
        )
        assert feature_names([group]) == names[start : start + width]
        start += width

    assert GROUP_WIDTHS["spectral"] == SPECTRAL_BANDS
    assert GROUP_WIDTHS["lbp"] == LBP_BINS


# --- the cases that would poison a training ---------------------------------


def test_a_constant_patch_produces_no_nan_and_no_infinity():
    """Zero variance is the division every group has, and none may return NaN.

    A flat patch is what a blown highlight or a lens cap produces, and one NaN
    feature standardises into NaN for every row of the fold. Each group answers
    it with a stated value instead: no third or fourth moment to report, no
    energy to distribute over bands, every neighbour tied with its centre, and a
    single grey level whose every pair is identical.
    """
    patch = np.full((16, 16), 137, dtype=np.uint8)
    vector = describe_patch(patch)

    assert np.isfinite(vector).all(), dict(zip(feature_names(), vector))
    assert _band_of("first_order", vector) == pytest.approx([137.0, 0.0, 0.0, 0.0])
    assert _band_of("spectral", vector) == pytest.approx(np.zeros(SPECTRAL_BANDS))

    lbp = np.zeros(LBP_BINS)
    lbp[8] = 1.0
    assert _band_of("lbp", vector) == pytest.approx(lbp)
    assert _band_of("glcm", vector) == pytest.approx([0.0, 1.0, 1.0, 1.0])


def test_a_patch_is_the_greyscale_one_cut_patches_produces():
    """The three identical channels of `patches.cut_patches`, as `uint8`.

    A colour patch is refused rather than read through its red channel, and a
    float patch rather than quantised as though it were bytes: both would be
    answered with a number, and a wrong descriptor cannot be told from a right
    one by anything downstream.
    """
    plane = _textured()
    replicated = np.repeat(plane[:, :, None], 3, axis=2)

    assert np.array_equal(describe_patch(replicated), describe_patch(plane))

    colour = replicated.copy()
    colour[0, 0, 1] = 0
    with pytest.raises(ValueError, match="identical"):
        describe_patch(colour)

    with pytest.raises(ValueError, match="uint8"):
        describe_patch(plane.astype(np.float64))


def test_the_descriptor_groups_are_computed_without_scikit_image():
    """Nothing here needs a second imaging library or a deep-learning stack.

    In a subprocess, because `sys.modules` is the whole session's and another
    module in this suite has already imported TensorFlow by the time this runs.
    Asserting against the shared table would test the run order, not the import.
    """
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import src.descriptors, sys; "
            "assert 'skimage' not in sys.modules, 'descriptors imported skimage'; "
            "assert 'tensorflow' not in sys.modules, "
            "'descriptors imported tensorflow'",
        ],
        cwd=ML_ROOT,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr
