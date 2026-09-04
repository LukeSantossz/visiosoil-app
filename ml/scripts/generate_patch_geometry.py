"""Regenerate the committed patch-geometry table (SPEC 0053).

The table is what both languages assert their grid against, in the shape
`test/fixtures/image_quality/golden.json` already uses: a change to the geometry
becomes a visible diff rather than a silent drift between Python and Dart.

Run from the `ml/` directory:

    python scripts/generate_patch_geometry.py
    python scripts/generate_patch_geometry.py --out somewhere.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config  # noqa: E402
from src.patches import patch_geometry  # noqa: E402
from src.scale import DISH_DIAMETER_MM  # noqa: E402

DEFAULT_OUT = (
    Path(__file__).resolve().parents[2]
    / "test"
    / "fixtures"
    / "patch_geometry"
    / "geometry.json"
)

#: The discs the table covers. The first is the application's refusal floor, the
#: last is the archive's dish, and the middle one is what ADR 0018 tabulates
#: between them.
DISC_DIAMETERS_MM = (70.0, 80.0, 90.0)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", help="where to write the table")
    parser.add_argument("--config", help="path to config.yaml")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    config = load_config(args.config)
    canonical = float(config["preprocessing"]["canonical_mm_per_px"])
    input_size = int(config["data"]["image_size"])
    min_patches = int(config["preprocessing"]["min_patches"])
    stride_fraction = float(config["preprocessing"]["patch_stride_fraction"])

    rows = []
    for disc_mm in DISC_DIAMETERS_MM:
        diameter_px = disc_mm / canonical
        geometry = patch_geometry(
            region_diameter_px=diameter_px,
            input_size=input_size,
            canonical_mm_per_px=canonical,
            min_patches=min_patches,
            stride_fraction=stride_fraction,
        )
        rows.append(
            {
                "disc_mm": disc_mm,
                "diameter_px": round(diameter_px, 4),
                "patch_count": geometry.count,
                "patch_mm": round(geometry.patch_mm, 4),
                "stride_px": geometry.stride_px,
                "inset_px": round(geometry.inset_px, 4),
            }
        )

    table = {
        "spec": "0053",
        "dish_diameter_mm": DISH_DIAMETER_MM,
        "canonical_mm_per_px": canonical,
        "input_size": input_size,
        "min_patches": min_patches,
        # Serialised, not just applied. The table is what the Dart half will
        # assert its grid against, and a reader cannot check a count without
        # the stride it was computed at.
        "patch_stride_fraction": stride_fraction,
        "rows": rows,
    }

    destination = Path(args.out) if args.out else DEFAULT_OUT
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(table, indent=2) + "\n", encoding="utf-8")
    print(f"{len(rows)} row(s) -> {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
