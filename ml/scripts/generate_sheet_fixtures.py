"""Generate the synthetic A4-sheet scenes the Dart reader is graded against (SPEC 0091).

Writes `test/fixtures/sheet/*.jpg` and `test/fixtures/sheet/golden.json`. Each
scene is a textured surface with, usually, a white A4 sheet laid on it in
perspective, and on the sheet the round soil patch the capture protocol asks
for. The golden records where the sheet's corners landed and the scale, and
`lib/core/services/descriptors/a4_sheet.dart` must recover them.

The geometry shares nothing with the Dart reader: the sheet is placed by
Pillow's `Image.transform(PERSPECTIVE)`. It is also deterministic across hosts,
so `tests/test_sheet_fixtures.py` can compare bytes:

- the corners are integer literals;
- the transform's coefficients are solved in exact fractions and rounded to
  float once;
- every texture is integer noise from a seeded PCG64;
- no transcendental function is called, so an AVX-512 libm cannot move a pixel
  (SPEC 0080).

Run from the `ml/` directory:

    python scripts/generate_sheet_fixtures.py
"""

from __future__ import annotations

import json
from fractions import Fraction
from pathlib import Path

import numpy as np
from PIL import Image

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPOSITORY_ROOT / "test" / "fixtures" / "sheet"

SHEET_MM = (210, 297)
#: The sheet is drawn at this many pixels per millimetre before it is placed.
SHEET_PX_PER_MM = 4
SHEET_PX = (SHEET_MM[0] * SHEET_PX_PER_MM, SHEET_MM[1] * SHEET_PX_PER_MM)

#: The protocol's round patch, centred on the sheet.
SOIL_DIAMETER_MM = 90
#: Marks for the rectification case, placed clear of the soil patch.
MARKS_MM = ((30, 30), (180, 30), (30, 267), (180, 267), (105, 40), (105, 257))
MARK_DIAMETER_MM = 5

JPEG_QUALITY = 90
SEED = 91

PAPER = (240, 238, 232)
SOIL = (112, 82, 58)
MARK = (24, 24, 24)
BACKGROUNDS = {
    "dark": (72, 58, 46),
    "grey": (126, 126, 124),
    # Close to the paper, so no edge separates them: the protocol's failure.
    "pale": (230, 228, 222),
}

#: Where each case puts the sheet's corners, in Pillow's continuous
#: coordinates (pixel i spans [i, i + 1]). The order is the sheet's own
#: (0, 0), (210, 0), (210, 297) and (0, 297) millimetres, so the first edge is a
#: short one and the second a long one.
CASES = (
    {
        "name": "frontal",
        "size": (900, 1200),
        "background": "grey",
        "corners": ((104, 110), (797, 110), (797, 1090), (104, 1090)),
        "expected": "sheet",
    },
    {
        "name": "tilted_15",
        "size": (900, 1200),
        "background": "dark",
        "corners": ((150, 170), (750, 170), (815, 1100), (85, 1100)),
        "expected": "sheet",
    },
    {
        "name": "tilted_30",
        "size": (900, 1200),
        "background": "dark",
        "corners": ((185, 210), (715, 210), (845, 1125), (55, 1125)),
        "expected": "sheet",
    },
    {
        # A 546 x 772 px sheet turned about 20 degrees in the plane, rounded to
        # whole pixels offline so that no cosine is computed here.
        "name": "rotated_20",
        "size": (900, 1200),
        "background": "grey",
        "corners": ((326, 144), (838, 331), (574, 1056), (62, 869)),
        "expected": "sheet",
    },
    {
        "name": "landscape",
        "size": (1200, 900),
        "background": "dark",
        "corners": ((1090, 104), (1090, 797), (110, 797), (110, 104)),
        "expected": "sheet",
    },
    {
        "name": "marks",
        "size": (900, 1200),
        "background": "dark",
        "corners": ((120, 130), (780, 120), (800, 1080), (100, 1095)),
        "expected": "sheet",
        "marks": True,
    },
    {
        "name": "cropped",
        "size": (900, 1200),
        "background": "grey",
        "corners": ((-60, 110), (633, 110), (633, 1090), (-60, 1090)),
        "expected": "cropped",
    },
    {
        "name": "no_sheet",
        "size": (900, 1200),
        "background": "dark",
        "corners": None,
        "expected": "notFound",
    },
    {
        "name": "pale_on_pale",
        "size": (900, 1200),
        "background": "pale",
        "corners": ((104, 110), (797, 110), (797, 1090), (104, 1090)),
        "expected": "notFound",
    },
)


def _textured(size, base, rng, coarse, fine):
    """``base`` with coarse blotches and fine grain, as integer noise.

    The coarse field is drawn at a sixteenth of the size and enlarged by
    Pillow's `BILINEAR`, which is fixed point and so the same on every host.
    """
    width, height = size
    small = (max(width // 16, 2), max(height // 16, 2))
    blotches = rng.integers(-coarse, coarse + 1, size=(small[1], small[0]), dtype=np.int16)
    blotches = np.asarray(
        Image.fromarray((blotches + 128).astype(np.uint8), mode="L").resize(
            size, Image.Resampling.BILINEAR
        ),
        dtype=np.int16,
    ) - 128
    grain = rng.integers(-fine, fine + 1, size=(height, width), dtype=np.int16)
    shade = (blotches + grain)[:, :, None]
    pixels = np.asarray(base, dtype=np.int16)[None, None, :] + shade
    return Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8), mode="RGB")


def _disc_mask(size, centre_mm, diameter_mm):
    """Pixels whose centres lie inside a disc, tested in whole numbers.

    A pixel (i, j) has its centre at (i + 1/2, j + 1/2) sheet pixels. Doubling
    every length keeps the comparison in integers.
    """
    width, height = size
    columns = 2 * np.arange(width, dtype=np.int64) + 1
    rows = 2 * np.arange(height, dtype=np.int64) + 1
    cx = 2 * centre_mm[0] * SHEET_PX_PER_MM
    cy = 2 * centre_mm[1] * SHEET_PX_PER_MM
    radius = diameter_mm * SHEET_PX_PER_MM
    dx = (columns - cx) ** 2
    dy = (rows - cy) ** 2
    return (dy[:, None] + dx[None, :]) <= radius * radius


def _sheet(rng, marks):
    """The bare sheet with the soil patch, and the marks when asked for."""
    sheet = np.asarray(_textured(SHEET_PX, PAPER, rng, coarse=3, fine=3)).copy()
    centre = (Fraction(SHEET_MM[0], 2), Fraction(SHEET_MM[1], 2))
    soil = np.asarray(_textured(SHEET_PX, SOIL, rng, coarse=20, fine=26))
    patch = _disc_mask(SHEET_PX, centre, SOIL_DIAMETER_MM)
    sheet[patch] = soil[patch]
    if marks:
        for position in MARKS_MM:
            sheet[_disc_mask(SHEET_PX, position, MARK_DIAMETER_MM)] = MARK
    return Image.fromarray(sheet, mode="RGB")


def _solve(matrix, vector):
    """Gaussian elimination over exact fractions."""
    size = len(vector)
    rows = [list(row) + [value] for row, value in zip(matrix, vector)]
    for column in range(size):
        pivot = next(r for r in range(column, size) if rows[r][column] != 0)
        rows[column], rows[pivot] = rows[pivot], rows[column]
        for r in range(size):
            if r != column and rows[r][column] != 0:
                factor = rows[r][column] / rows[column][column]
                rows[r] = [a - factor * b for a, b in zip(rows[r], rows[column])]
    return [rows[i][size] / rows[i][i] for i in range(size)]


def perspective_coefficients(scene_corners):
    """Pillow's eight coefficients, mapping a scene point to a sheet point.

    `Image.transform(PERSPECTIVE)` samples the source at
    ((a x + b y + c) / (g x + h y + 1), (d x + e y + f) / (g x + h y + 1)) for an
    output point (x, y). The source here is the sheet image, whose corners are
    (0, 0), (W, 0), (W, H) and (0, H).
    """
    width, height = SHEET_PX
    sheet_corners = ((0, 0), (width, 0), (width, height), (0, height))
    matrix, vector = [], []
    for (x, y), (u, v) in zip(scene_corners, sheet_corners):
        x, y, u, v = (Fraction(value) for value in (x, y, u, v))
        matrix.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        vector.append(u)
        matrix.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        vector.append(v)
    return tuple(float(value) for value in _solve(matrix, vector))


def _length(a, b):
    return float(np.hypot(b[0] - a[0], b[1] - a[1]))


def render(case, rng):
    """One scene, and what the golden says about it."""
    scene = _textured(case["size"], BACKGROUNDS[case["background"]], rng, coarse=18, fine=6)
    entry = {
        "name": case["name"],
        "file": f"sheet_{case['name']}.jpg",
        "width": case["size"][0],
        "height": case["size"][1],
        "expected": case["expected"],
    }
    corners = case["corners"]
    if corners is not None:
        coefficients = perspective_coefficients(corners)
        sheet = _sheet(rng, case.get("marks", False))
        placed = sheet.transform(
            case["size"], Image.Transform.PERSPECTIVE, coefficients, Image.Resampling.BICUBIC
        )
        mask = Image.new("L", SHEET_PX, 255).transform(
            case["size"], Image.Transform.PERSPECTIVE, coefficients, Image.Resampling.BILINEAR
        )
        scene = Image.composite(placed, scene, mask)
        # The Dart reader puts a pixel's centre on the integer, Pillow at + 1/2.
        entry["corners"] = [[x - 0.5, y - 0.5] for x, y in corners]
        long_edges = (_length(corners[1], corners[2]) + _length(corners[3], corners[0])) / 2
        entry["mm_per_px"] = SHEET_MM[1] / long_edges
        entry["soil_mm"] = {
            "centre": [SHEET_MM[0] / 2, SHEET_MM[1] / 2],
            "diameter": SOIL_DIAMETER_MM,
        }
        if case.get("marks"):
            entry["marks_mm"] = [list(position) for position in MARKS_MM]
    return scene, entry


def generate(out_dir: Path) -> dict:
    """Write every scene and the golden to ``out_dir``, and return the golden."""
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.Generator(np.random.PCG64(SEED))
    cases = []
    for case in CASES:
        scene, entry = render(case, rng)
        scene.save(out_dir / entry["file"], "JPEG", quality=JPEG_QUALITY)
        cases.append(entry)
    golden = {
        "spec": "SPEC 0091",
        "sheet_mm": list(SHEET_MM),
        "jpeg_quality": JPEG_QUALITY,
        "cases": cases,
    }
    (out_dir / "golden.json").write_text(json.dumps(golden, indent=2) + "\n", encoding="utf-8")
    return golden


def main() -> None:
    golden = generate(FIXTURES_DIR)
    print(f"{len(golden['cases'])} scenes written to {FIXTURES_DIR}")


if __name__ == "__main__":
    main()
