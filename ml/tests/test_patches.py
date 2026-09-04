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

CANONICAL = 0.12920342774728033
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
    diameter_px = 55.0 / CANONICAL  # carries five patches, below the floor

    with pytest.raises(ValueError) as raised:
        patch_geometry(
            region_diameter_px=diameter_px,
            input_size=INPUT_SIZE,
            canonical_mm_per_px=CANONICAL,
            min_patches=9,
        )

    message = str(raised.value)
    assert "5 patch" in message
    assert "floor is 9" in message


@pytest.mark.parametrize(
    "disc_mm,expected",
    [
        (50.0, 5),
        (58.4, 5),
        (58.5, 9),
        (70.0, 9),
        (71.0, 13),
        (80.0, 21),
        (90.0, 25),
    ],
)
def test_the_patch_count_steps_where_the_geometry_says_it_does(disc_mm, expected):
    """Pins the floor, which is not where ADR 0018 rounds it to.

    Nine patches are reached at **58.6 mm**, not at the "roughly 70 mm" that
    record states — 70 mm is inside the same step, so its tabulated 9 is right
    and its floor is conservative. The difference is the application's to
    decide, since it is the side that refuses a disc, and it is recorded here
    rather than left to be rediscovered.

    The step is pinned from both sides, because the floor moves with the
    canonical — it is `2 x half-diagonal x canonical` — and a table asserting
    only the passing side would not notice it moving.
    """
    geometry_or_error = None
    try:
        geometry_or_error = patch_geometry(
            region_diameter_px=disc_mm / CANONICAL,
            input_size=INPUT_SIZE,
            canonical_mm_per_px=CANONICAL,
            min_patches=1,
        ).count
    except ValueError as error:  # pragma: no cover - only if the floor moves
        geometry_or_error = str(error)

    assert geometry_or_error == expected


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
    """One value, two files, and a test that refuses them to drift.

    Bit equality, and the config carries the unrounded float because of it.
    Rounding the canonical for readability is not free: 0.1292 is finer than the
    percentile it stands for, so it refuses the photograph whose reading defines
    that percentile and twelve photographs leave training where the measurement
    says eleven. The test below is what says so.
    """
    from src.config import load_config

    configured = load_config()["preprocessing"]["canonical_mm_per_px"]
    recorded = json.loads(RECORD_PATH.read_text(encoding="utf-8"))["canonical_mm_per_px"]

    assert configured == recorded


def test_rounding_the_canonical_would_refuse_a_twelfth_photograph():
    """Why `config.yaml` carries an unrounded constant.

    Rounding to the four decimals the file would prefer moves the canonical
    below the percentile it stands for, and the photograph that *is* the
    percentile then reads as coarser than the scale derived from it. The cost of
    readability here is one sample group leaving training, so it is measured
    rather than argued about.
    """
    from src.config import load_config

    configured = load_config()["preprocessing"]["canonical_mm_per_px"]
    readings = [
        row["mm_per_px"]
        for row in json.loads(RECORD_PATH.read_text(encoding="utf-8"))["photographs"]
        if row["mm_per_px"] is not None
    ]

    assert sum(1 for value in readings if value > configured) == 11
    assert sum(1 for value in readings if value > round(configured, 4)) == 12


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


# --- the manifest carries what the grid needs ------------------------------


def test_the_manifest_carries_the_measured_disc_geometry(tmp_path):
    """A diameter with no centre locates nothing, so all four are carried."""
    from dataclasses import replace

    from src.manifest import SCALE_COLUMNS, read_manifest, write_manifest
    from tests.support import CLASSES, write_image_version

    root = write_image_version(tmp_path, {"s-1": [("dish", _dish(400, 150.0))]})
    manifest = read_manifest(root, CLASSES)
    measured = [
        replace(
            row,
            scale={
                "mm_per_px": 0.1,
                "disc_diameter_px": 300.0,
                "disc_centre_x_px": 200.0,
                "disc_centre_y_px": 200.0,
                "frame_width_px": 400.0,
                "frame_height_px": 400.0,
            },
        )
        for row in manifest.rows
    ]
    write_manifest(root, measured)

    reread = read_manifest(root, CLASSES)

    assert set(SCALE_COLUMNS) == set(reread.rows[0].scale)
    assert reread.rows[0].scale["disc_diameter_px"] == pytest.approx(300.0)


def test_a_non_positive_diameter_is_refused_by_name(tmp_path):
    from src.manifest import ManifestError, read_manifest
    from tests.support import CLASSES, write_image_version

    root = write_image_version(tmp_path, {"s-1": [("dish", _dish(400, 150.0))]})
    path = root / "manifest.csv"
    text = path.read_text(encoding="utf-8").rstrip("\n").split("\n")
    text[0] += ",disc_diameter_px"
    text[1] += ",0"
    path.write_text("\n".join(text) + "\n", encoding="utf-8")

    with pytest.raises(ManifestError, match="must be positive"):
        read_manifest(root, CLASSES)


def test_a_version_without_a_measured_scale_is_reported_by_name(tmp_path):
    """Checked where it is needed, not at parse time: ingest precedes measure."""
    from src.manifest import check_scale_columns, read_manifest
    from tests.support import CLASSES, write_image_version

    root = write_image_version(tmp_path, {"s-1": [("dish", _dish(400, 150.0))]})

    problems = check_scale_columns(read_manifest(root, CLASSES))

    assert len(problems) == 1
    assert "measure_scale.py" in problems[0]


# --- a grid that leaves the photograph ---------------------------------------


def test_a_grid_that_leaves_the_frame_is_refused_by_name():
    """The dish can be wide enough for a grid and still hang off the frame.

    `patch_geometry` measures the dish against the patch, never against the
    photograph, so a dish near an edge passes every geometric check and then
    fails inside `cut_patches` — historically with an unnamed `ValueError`,
    which in the input pipeline surfaces mid-epoch wrapped by tf.data.
    """
    diameter = 700.0
    geometry = patch_geometry(
        region_diameter_px=diameter,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
    )
    assert geometry.count == 25

    frame = Image.new("RGB", (800, 800), (128, 128, 128))

    with pytest.raises(ValueError, match=PatchRefusal.OUTSIDE_FRAME.value):
        cut_patches(
            frame,
            centre_y=400.0,
            centre_x=120.0,
            region_diameter_px=diameter,
            input_size=INPUT_SIZE,
            canonical_mm_per_px=CANONICAL,
        )


def test_the_geometry_table_is_generated_at_the_configured_stride():
    """The fixture is the contract both languages assert their grid against.

    Generating it at the default stride while the pipeline reads the configured
    one would let the two disagree the moment the configuration changed, and
    this table is exactly the artefact that exists to stop that.
    """
    from src.config import load_config

    table = json.loads(GEOMETRY_PATH.read_text(encoding="utf-8"))
    configured = load_config()["preprocessing"]["patch_stride_fraction"]

    assert table["patch_stride_fraction"] == configured
    assert table["rows"][0]["stride_px"] == pytest.approx(
        table["input_size"] * configured
    )
