"""Generate the cross-language patch-grid golden (SPEC 0081, ADR 0025).

Writes `test/fixtures/patches/golden.json`: resample cases, luma cases, grid
geometry cases and whole-photograph pipeline cases, each with what the Python
reference returns for it. `lib/core/services/descriptors/patch_grid.dart` must
reproduce every one byte for byte, and `tests/test_patch_golden.py` asserts that
Python still does.

The pipeline cases go through `src.dataset._photograph_patches` itself, the cut
training uses, by way of a lossless PNG, so the golden cannot drift from the
path that produced every fold artefact.

Frames are stored as base64 of the raw interleaved RGB bytes, and patches as
base64 of the raw grey plane. The pipeline cases cut 16 px patches so every
patch byte fits in the file; the code has no branch that depends on the size,
and the real configuration's geometry is asserted by the geometry cases.

Run from the `ml/` directory:

    python scripts/generate_patch_golden.py
"""

from __future__ import annotations

import base64
import json
import math
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Union

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config  # noqa: E402
from src.dataset import _photograph_patches  # noqa: E402
from src.image_quality import LUMA_B, LUMA_G, LUMA_R  # noqa: E402
from src.patches import (  # noqa: E402
    PatchRefusal,
    patch_geometry,
    resample_to_canonical,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "patches" / "golden.json"

#: A patch centre this close to its limit is refused as a fixture, because
#: Dart's `sqrt` and CPython's `hypot` could disagree about it (SPEC 0081).
HYPOT_MARGIN = 1e-6


def _b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode("ascii")


def _noise(seed: int, height: int, width: int) -> np.ndarray:
    return np.random.default_rng(seed).integers(0, 256, size=(height, width, 3)).astype(np.uint8)


def frame_image(case: dict) -> Image.Image:
    """A case's frame as the RGB image Pillow resamples."""
    raw = base64.b64decode(case["rgb"])
    plane = np.frombuffer(raw, dtype=np.uint8).reshape(case["height"], case["width"], 3)
    return Image.fromarray(plane, "RGB")


def python_grey(rgb) -> int:
    """`cut_patches`' luma for one pixel: the same expression, the same rounding."""
    red, green, blue = (np.float64(channel) for channel in rgb)
    return int(np.rint(LUMA_R * red + LUMA_G * green + LUMA_B * blue).clip(0.0, 255.0))


def refusal_name(error: Exception) -> Union[str, None]:
    """The `PatchRefusal` a refusal names, or None if it names none."""
    message = str(error)
    for refusal in PatchRefusal:
        if refusal.value in message:
            return refusal.value
    return None


def canonical_diameter(case: dict) -> float:
    """The region's diameter in canonical pixels, as `_canonical_region` moves it."""
    ratio = case["measured_mm_per_px"] / case["canonical_mm_per_px"]
    return case["diameter_px"] * ratio


def python_patches(case: dict) -> Union[List[np.ndarray], str]:
    """The grey planes the training cut returns for a pipeline case, or its refusal."""
    cfg = {
        "data": {"image_size": case["patch_px"]},
        "preprocessing": {
            "canonical_mm_per_px": case["canonical_mm_per_px"],
            "min_patches": case["min_patches"],
            "patch_stride_fraction": case["stride_fraction"],
        },
    }
    measurement = {
        "mm_per_px": case["measured_mm_per_px"],
        "disc_centre_y_px": case["centre_y_px"],
        "disc_centre_x_px": case["centre_x_px"],
        "disc_diameter_px": case["diameter_px"],
    }
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "frame.png"
        frame_image(case).save(path)
        try:
            patches = _photograph_patches({"path": str(path)}, measurement, cfg)
        except ValueError as refusal:
            name = refusal_name(refusal)
            if name is None:
                raise
            return name
    # The three channels are identical; the descriptors read one of them.
    return [np.ascontiguousarray(patch[:, :, 0]) for patch in patches]


def _require_off_the_hypot_boundary(diameter: float, patch_px: int, stride_fraction: float) -> None:
    stride = patch_px * stride_fraction
    limit = diameter / 2.0 - patch_px * math.sqrt(2.0) / 2.0
    steps = int(abs(limit) // stride) + 1
    # Both lattices: the centred one, and the one moved by half a stride (SPEC 0141).
    for half in (0.0, 0.5):
        for row in range(-steps - 1, steps + 1):
            for column in range(-steps - 1, steps + 1):
                distance = math.hypot((row + half) * stride, (column + half) * stride)
                if abs(distance - (limit + 1e-9)) <= HYPOT_MARGIN:
                    raise ValueError(
                        f"a region of {diameter} px puts a patch centre within "
                        f"{HYPOT_MARGIN} px of its limit, where the two languages "
                        f"could disagree; choose another diameter"
                    )


# --- resample -----------------------------------------------------------------

#: (name, seed, height, width, measured, canonical)
RESAMPLE_CASES = [
    ("identity", 1, 17, 23, 0.125, 0.125),
    # 0.1 / 0.2 is exactly 0.5: 61 x 0.5 rounds half to 30, 47 x 0.5 to 24.
    ("half_way_sides", 2, 47, 61, 0.1, 0.2),
    ("strong_reduction", 3, 50, 64, 0.03, 0.1),
    ("real_canonical", 4, 43, 57, 0.0943, 0.12920342774728033),
    # Rounds back to the size it started at, where Pillow copies rather than
    # resamples.
    ("same_size", 5, 17, 23, 0.1249, 0.125),
]


def _resample_case(name, seed, height, width, measured, canonical) -> dict:
    case = {
        "name": name,
        "height": height,
        "width": width,
        "rgb": _b64(_noise(seed, height, width).tobytes()),
        "measured_mm_per_px": measured,
        "canonical_mm_per_px": canonical,
    }
    resized, _ = resample_to_canonical(frame_image(case), measured, canonical)
    case["out_width"], case["out_height"] = resized.size
    case["resampled"] = _b64(np.asarray(resized).tobytes())
    return case


# --- luma ---------------------------------------------------------------------


def _luma_cases() -> List[dict]:
    """Every 400th triple whose luma is exactly .5, plus a few that are not."""
    values = np.arange(256, dtype=np.float64)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    luma = LUMA_R * red + LUMA_G * green + LUMA_B * blue
    on_half = np.argwhere(luma - np.floor(luma) == 0.5)[::400]
    triples = [tuple(int(channel) for channel in row) for row in on_half]
    triples += [(0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255), (17, 130, 201)]
    return [{"rgb": list(triple), "grey": python_grey(triple)} for triple in triples]


# --- geometry -----------------------------------------------------------------


#: The floor the first geometry and pipeline cases were written at. They keep
#: it whatever the configured floor is, so they still pin the step to nine.
NINE_PATCHES = 9

#: The floor SPEC 0141's cases are written at, where a disc too small for the
#: centred five moves to the half-stride block of four.
FOUR_PATCHES = 4


def _geometry_cases(cfg: dict) -> List[dict]:
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    patch_px = cfg["data"]["image_size"]
    stride_fraction = cfg["preprocessing"]["patch_stride_fraction"]
    stride = patch_px * stride_fraction
    inset = patch_px * math.sqrt(2.0) / 2.0
    # Nine patches need the corner offsets inside the limit: an inset of a
    # half-diagonal plus a stride along the diagonal.
    floor = 2.0 * (inset + stride * math.sqrt(2.0))
    # The half-stride block of four needs half that diagonal (SPEC 0141).
    block = 2.0 * (inset + stride * math.sqrt(2.0) / 2.0)

    diameters = {
        "disc_70_mm": (70.0 / canonical, NINE_PATCHES),
        "disc_80_mm": (80.0 / canonical, NINE_PATCHES),
        "disc_90_mm": (90.0 / canonical, NINE_PATCHES),
        "just_below_the_floor": (floor - 0.01, NINE_PATCHES),
        "just_above_the_floor": (floor + 0.01, NINE_PATCHES),
        "no_room_for_one_patch": (200.0, NINE_PATCHES),
        "disc_47_5_mm_on_the_half_stride_grid": (47.5 / canonical, FOUR_PATCHES),
        "disc_51_mm_on_the_centred_five": (51.0 / canonical, FOUR_PATCHES),
        "just_below_the_half_stride_block": (block - 0.01, FOUR_PATCHES),
        "just_above_the_half_stride_block": (block + 0.01, FOUR_PATCHES),
    }
    cases = []
    for name, (diameter, min_patches) in diameters.items():
        _require_off_the_hypot_boundary(diameter, patch_px, stride_fraction)
        case = {
            "name": name,
            "region_diameter_px": diameter,
            "patch_px": patch_px,
            "canonical_mm_per_px": canonical,
            "min_patches": min_patches,
            "stride_fraction": stride_fraction,
        }
        try:
            geometry = patch_geometry(
                region_diameter_px=diameter,
                input_size=patch_px,
                canonical_mm_per_px=canonical,
                min_patches=min_patches,
                stride_fraction=stride_fraction,
            )
        except ValueError as refusal:
            case["refusal"] = refusal_name(refusal)
        else:
            case.update(
                count=geometry.count,
                stride_px=geometry.stride_px,
                inset_px=geometry.inset_px,
                patch_mm=geometry.patch_mm,
                offsets=[list(offset) for offset in geometry.offsets],
            )
        cases.append(case)
    return cases


# --- pipeline -----------------------------------------------------------------


def _half_luma_frame(height: int, width: int) -> np.ndarray:
    """A frame tiled with triples whose luma is exactly .5."""
    values = np.arange(256, dtype=np.float64)
    red, green, blue = np.meshgrid(values, values, values, indexing="ij")
    luma = LUMA_R * red + LUMA_G * green + LUMA_B * blue
    on_half = np.argwhere(luma - np.floor(luma) == 0.5).astype(np.uint8)
    picks = np.random.default_rng(90).choice(len(on_half), size=height * width)
    return on_half[picks].reshape(height, width, 3)


#: (name, frame, measured, canonical, centre_y, centre_x, diameter, min_patches)
def _pipeline_inputs() -> list:
    nine = NINE_PATCHES
    return [
        ("reduced_nine_patches", _noise(10, 80, 90), 0.1, 0.125, 40.3, 45.7, 62.0, nine),
        # At the canonical, so nothing resamples, and on a half pixel, so every
        # patch corner rounds half to even.
        ("at_canonical_on_a_half_pixel", _noise(11, 72, 80), 0.125, 0.125, 36.5, 40.5, 50.0, nine),
        ("reduced_twenty_one_patches", _noise(12, 96, 100), 0.09, 0.125, 48.6, 50.1, 60.0 / 0.72, nine),
        ("luma_on_half", _half_luma_frame(48, 48), 0.125, 0.125, 24.0, 24.0, 46.0, nine),
        ("too_coarse", _noise(13, 48, 48), 0.14, 0.125, 24.0, 24.0, 46.0, nine),
        ("region_too_small", _noise(14, 48, 48), 0.125, 0.125, 24.0, 24.0, 30.0, nine),
        ("outside_frame", _noise(15, 48, 48), 0.125, 0.125, 12.0, 24.0, 46.0, nine),
        # A 36 px disc once reduced: the centred grid holds one patch, and the
        # half-stride grid the block of four at (+-4, +-4) (SPEC 0141).
        ("reduced_half_stride_four", _noise(16, 60, 60), 0.1, 0.125, 30.3, 29.8, 45.0, FOUR_PATCHES),
    ]


def _pipeline_cases() -> List[dict]:
    cases = []
    for name, frame, measured, canonical, centre_y, centre_x, diameter, min_patches in (
        _pipeline_inputs()
    ):
        height, width, _ = frame.shape
        case = {
            "name": name,
            "height": height,
            "width": width,
            "rgb": _b64(frame.tobytes()),
            "measured_mm_per_px": measured,
            "canonical_mm_per_px": canonical,
            "centre_y_px": centre_y,
            "centre_x_px": centre_x,
            "diameter_px": diameter,
            "patch_px": 16,
            "stride_fraction": 0.5,
            "min_patches": min_patches,
        }
        if measured <= canonical:
            _require_off_the_hypot_boundary(canonical_diameter(case), 16, 0.5)
        outcome = python_patches(case)
        if isinstance(outcome, str):
            case["refusal"] = outcome
        else:
            case["patches"] = [_b64(patch.tobytes()) for patch in outcome]
        cases.append(case)
    return cases


def build_golden() -> Dict:
    cfg = load_config()
    return {
        "spec": "0081",
        "generator": "ml/scripts/generate_patch_golden.py",
        "resample": [_resample_case(*case) for case in RESAMPLE_CASES],
        "luma": _luma_cases(),
        "geometry": _geometry_cases(cfg),
        "pipeline": _pipeline_cases(),
    }


def render(golden: Dict) -> str:
    return json.dumps(golden, indent=2) + "\n"


def main() -> None:
    GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN_PATH.write_text(render(build_golden()), encoding="utf-8")
    print(f"wrote {GOLDEN_PATH}")


if __name__ == "__main__":
    main()
