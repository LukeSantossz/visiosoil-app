"""Acceptance criteria for the scale-normalised greyscale patch grid (SPEC 0053).

Each test name matches an acceptance criterion in
`docs/specs/0053-train-on-scale-normalised-greyscale-patches.md`.

Everything here runs on rendered images. The grid is arithmetic over a measured
scale and a located circle, so it needs no dataset and no TensorFlow.
"""

import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from src.image_quality import LUMA_B, LUMA_G, LUMA_R
from src.patches import (
    PatchGeometry,
    PatchRefusal,
    cut_patches,
    patch_geometry,
    resample_to_canonical,
)
from src.scale import DISH_DIAMETER_MM

ML_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ML_ROOT.parent
GEOMETRY_PATH = REPO_ROOT / "test" / "fixtures" / "patch_geometry" / "geometry.json"
RECORD_PATH = ML_ROOT / "measurements" / "dish-scale-v1.json"

CANONICAL = 0.1292
INPUT_SIZE = 160


def _dish(side: int, outer_radius: float, centre=None) -> Image.Image:
    """A dish rendered large enough to carry a patch grid."""
    cy, cx = centre if centre is not None else (side / 2.0, side / 2.0)
    ys, xs = np.mgrid[0:side, 0:side]
    radius = np.hypot(ys - cy, xs - cx)
    plane = np.full((side, side), 235.0)
    plane[radius <= outer_radius] = 130.0
    plane[radius <= outer_radius * 0.98] = 210.0
    plane[radius <= outer_radius * 0.94] = 70.0
    return Image.fromarray(
        np.dstack([plane, plane, plane]).astype(np.uint8), mode="RGB"
    )


def _textured_dish(side: int, outer_radius: float, seed: int = 3) -> Image.Image:
    """A dish whose soil carries colour, so greyscale is observable."""
    generator = np.random.default_rng(seed)
    cy = cx = side / 2.0
    ys, xs = np.mgrid[0:side, 0:side]
    radius = np.hypot(ys - cy, xs - cx)
    noise = generator.uniform(-30.0, 30.0, size=(side, side))
    red = np.where(radius <= outer_radius * 0.94, 150.0 + noise, 235.0)
    green = np.where(radius <= outer_radius * 0.94, 95.0 + noise, 235.0)
    blue = np.where(radius <= outer_radius * 0.94, 60.0 + noise, 235.0)
    for plane in (red, green, blue):
        plane[(radius > outer_radius * 0.94) & (radius <= outer_radius)] = 150.0
    stacked = np.dstack([red, green, blue]).clip(0.0, 255.0)
    return Image.fromarray(stacked.astype(np.uint8), mode="RGB")


# --- resampling ------------------------------------------------------------


def test_resamples_a_photograph_to_the_canonical_scale():
    """A finer photograph is brought down to the canonical, not left alone."""
    image = _dish(side=1400, outer_radius=500.0)

    resampled, scale = resample_to_canonical(image, measured_mm_per_px=0.05,
                                             canonical_mm_per_px=CANONICAL)

    assert scale == pytest.approx(CANONICAL)
    expected = 1400 * (0.05 / CANONICAL)
    assert resampled.size[0] == pytest.approx(expected, abs=1.0)


def test_refuses_to_upsample_a_coarse_photograph():
    image = _dish(side=900, outer_radius=300.0)

    with pytest.raises(ValueError, match=PatchRefusal.TOO_COARSE.value):
        resample_to_canonical(image, measured_mm_per_px=0.20,
                              canonical_mm_per_px=CANONICAL)


def test_a_photograph_already_at_the_canonical_is_untouched():
    """Equality is not an upsample, and resizing it would only lose detail."""
    image = _dish(side=900, outer_radius=300.0)

    resampled, _ = resample_to_canonical(image, measured_mm_per_px=CANONICAL,
                                         canonical_mm_per_px=CANONICAL)

    assert resampled.size == image.size


# --- geometry --------------------------------------------------------------


@pytest.mark.parametrize(
    "disc_mm,expected", [(70.0, 9), (80.0, 21), (90.0, 25)]
)
def test_the_patch_counts_reproduce_the_adr_0018_table(disc_mm, expected):
    """9, 21 and 25 — computed from the geometry, never asserted as constants."""
    diameter_px = disc_mm / CANONICAL

    geometry = patch_geometry(
        region_diameter_px=diameter_px,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    assert geometry.count == expected


def test_patch_geometry_is_derived_not_hardcoded():
    geometry = patch_geometry(
        region_diameter_px=90.0 / CANONICAL,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    assert geometry.patch_mm == pytest.approx(INPUT_SIZE * CANONICAL)
    assert geometry.stride_px == pytest.approx(INPUT_SIZE / 2.0)
    assert geometry.inset_px == pytest.approx(INPUT_SIZE * math.sqrt(2.0) / 2.0)


def test_every_patch_lies_inside_the_located_region():
    """The corners too, which is what the half-diagonal inset is for."""
    radius = (90.0 / CANONICAL) / 2.0
    geometry = patch_geometry(
        region_diameter_px=2.0 * radius,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    half = INPUT_SIZE / 2.0
    for offset_y, offset_x in geometry.offsets:
        for corner_y in (offset_y - half, offset_y + half):
            for corner_x in (offset_x - half, offset_x + half):
                assert math.hypot(corner_y, corner_x) <= radius + 1e-9


def test_a_half_width_inset_would_put_corners_outside():
    """The correction SPEC 0037's prose needed, asserted rather than asserted at."""
    radius = (90.0 / CANONICAL) / 2.0
    half = INPUT_SIZE / 2.0
    limit = radius - half  # the half-width inset SPEC 0037 used to specify

    escaping = [
        (y, x)
        for y in np.arange(-radius, radius, INPUT_SIZE / 2.0)
        for x in np.arange(-radius, radius, INPUT_SIZE / 2.0)
        if math.hypot(y, x) <= limit
        and math.hypot(abs(y) + half, abs(x) + half) > radius
    ]

    assert escaping, "a half-width inset must admit at least one escaping patch"


def test_refuses_a_region_too_small_for_nine_patches():
    diameter_px = 50.0 / CANONICAL  # far below the ~70 mm floor

    with pytest.raises(ValueError, match=PatchRefusal.REGION_TOO_SMALL.value):
        patch_geometry(
            region_diameter_px=diameter_px,
            input_size=INPUT_SIZE,
            canonical_mm_per_px=CANONICAL,
            min_patches=9,
        )


def test_the_refusal_names_the_count_it_could_have_produced():
    diameter_px = 65.0 / CANONICAL

    with pytest.raises(ValueError) as raised:
        patch_geometry(
            region_diameter_px=diameter_px,
            input_size=INPUT_SIZE,
            canonical_mm_per_px=CANONICAL,
            min_patches=9,
        )

    assert "9" in str(raised.value)
    assert any(character.isdigit() for character in str(raised.value))


# --- cutting ---------------------------------------------------------------


def test_patches_are_greyscale_through_the_shared_luma():
    """One luma definition, and three identical channels in the tensor."""
    image = _textured_dish(side=1000, outer_radius=380.0)

    patches = cut_patches(
        image,
        centre_y=500.0,
        centre_x=500.0,
        region_diameter_px=2.0 * 380.0,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    first = patches[0]
    assert first.shape == (INPUT_SIZE, INPUT_SIZE, 3)
    assert np.array_equal(first[..., 0], first[..., 1])
    assert np.array_equal(first[..., 1], first[..., 2])

    source = np.asarray(image, dtype=np.float64)
    expected = LUMA_R * source[..., 0] + LUMA_G * source[..., 1] + LUMA_B * source[..., 2]
    assert first[..., 0].min() >= expected.min() - 1.0
    assert first[..., 0].max() <= expected.max() + 1.0


def test_cutting_yields_the_geometry_count():
    radius = 380.0
    image = _textured_dish(side=1000, outer_radius=radius)
    geometry = patch_geometry(
        region_diameter_px=2.0 * radius,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    patches = cut_patches(
        image,
        centre_y=500.0,
        centre_x=500.0,
        region_diameter_px=2.0 * radius,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    assert len(patches) == geometry.count


def test_cutting_is_deterministic():
    image = _textured_dish(side=1000, outer_radius=380.0)
    arguments = dict(
        centre_y=500.0,
        centre_x=500.0,
        region_diameter_px=760.0,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    first = cut_patches(image, **arguments)
    second = cut_patches(image, **arguments)

    assert len(first) == len(second)
    assert all(np.array_equal(a, b) for a, b in zip(first, second))


# --- the committed geometry table ------------------------------------------


def test_the_committed_geometry_table_matches_the_generator(tmp_path):
    generator = _load_script("generate_patch_geometry")
    written = tmp_path / "geometry.json"

    generator.main(["--out", str(written)])

    assert written.read_bytes() == GEOMETRY_PATH.read_bytes()


def test_the_geometry_table_holds_the_adr_0018_rows():
    table = json.loads(GEOMETRY_PATH.read_text(encoding="utf-8"))

    by_disc = {row["disc_mm"]: row for row in table["rows"]}
    assert by_disc[70.0]["patch_count"] == 9
    assert by_disc[80.0]["patch_count"] == 21
    assert by_disc[90.0]["patch_count"] == 25
    assert table["canonical_mm_per_px"] == pytest.approx(CANONICAL)


def test_the_config_canonical_matches_the_measurement_record():
    """One value, two files, and a test that refuses them to drift."""
    from src.config import load_config

    configured = load_config()["preprocessing"]["canonical_mm_per_px"]
    recorded = json.loads(RECORD_PATH.read_text(encoding="utf-8"))["canonical_mm_per_px"]

    assert configured == pytest.approx(recorded, rel=1e-6)


def test_the_geometry_table_needs_no_tensorflow():
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import src.patches, sys; "
            "assert 'tensorflow' not in sys.modules, 'patches imported tensorflow'",
        ],
        cwd=ML_ROOT,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr


def _load_script(name: str):
    import importlib.util

    path = ML_ROOT / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_dish_diameter_is_the_one_the_scale_reader_uses():
    """The geometry and the scale reader must not carry two 90 mm constants."""
    table = json.loads(GEOMETRY_PATH.read_text(encoding="utf-8"))

    assert table["dish_diameter_mm"] == DISH_DIAMETER_MM


def test_patch_geometry_is_a_value_object_with_its_offsets():
    geometry = patch_geometry(
        region_diameter_px=90.0 / CANONICAL,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )

    assert isinstance(geometry, PatchGeometry)
    assert len(geometry.offsets) == geometry.count
    assert geometry.offsets == tuple(sorted(geometry.offsets))
