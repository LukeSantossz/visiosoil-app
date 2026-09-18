"""Builds the two packed grids the app resolves a site key from.

Run after the source shapefiles are downloaded (see `corpus/README.md`). Output
goes to `corpus/out/`, git-ignored, and becomes an asset only when a release is
made — the same rule the cells follow.

The lattice covers Brazil's bounding box at 0.1°, which is roughly 11 km. Both
source maps are generalised at 1:5 000 000, so a finer lattice would encode
precision the sources do not have; §5.2 accepts that the error is confined to
transition bands.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from src.clay_activity import family_for_soil_class
from src.grids import GridSpec, write_packed_grid, rasterise
from src.keys import BIOMES, CLAY_ACTIVITIES

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
OUT_DIR = Path(__file__).resolve().parent.parent / "out"

# Brazil's bounding box, rounded outward to whole tenths of a degree so the
# lattice origin is exact rather than a float that drifts.
MIN_LAT_MILLI = -34_000
MIN_LON_MILLI = -74_000
ROWS = 400  # -34.0 to 6.0
COLS = 400  # -74.0 to -34.0
CELL_MILLI = 100

CLAY_KIND = 1
BIOME_KIND = 2

_BIOME_BY_NAME = {
    "amazonia": "amazonia",
    "caatinga": "caatinga",
    "cerrado": "cerrado",
    "mata atlantica": "mata_atlantica",
    "pampa": "pampa",
    "pantanal": "pantanal",
}
"""The legend's `NOM_BIOMA` values, normalised. Its four `Massa Dagua` entries
are water and resolve to nothing."""

_UNACCENTED = str.maketrans(
    "áàãâäéêèëíîìïóôõòöúûùüçñ", "aaaaaeeeeiiiiooooouuuucn"
)


def _normalise(value: str) -> str:
    return value.strip().lower().translate(_UNACCENTED)


def clay_value(name: str) -> int:
    """One-based index into [CLAY_ACTIVITIES], or 0 for unresolved."""
    family = family_for_soil_class(name)
    return CLAY_ACTIVITIES.index(family) + 1 if family else 0


def biome_value(name: str) -> int:
    """One-based index into [BIOMES], or 0 for water and anything unknown."""
    key = _BIOME_BY_NAME.get(_normalise(name))
    return BIOMES.index(key) + 1 if key else 0


def build(out_dir: Path = OUT_DIR, data_dir: Path = DATA_DIR) -> dict[str, int]:
    """Writes both grids and returns how many cells each resolved."""
    out_dir.mkdir(parents=True, exist_ok=True)
    written: dict[str, int] = {}

    for kind, layer, field, value_for, source_id, filename in (
        (
            CLAY_KIND,
            data_dir / "solos" / "Solos_5000",
            "DSC_COMPON",
            clay_value,
            "ibge-solos-5000mil-2018",
            "clay-activity-grid.bin",
        ),
        (
            BIOME_KIND,
            data_dir / "biomas" / "Biomas5000",
            "NOM_BIOMA",
            biome_value,
            "ibge-biomas-5000mil-2018",
            "biome-grid.bin",
        ),
    ):
        spec = GridSpec(
            kind=kind,
            cell_milli_degrees=CELL_MILLI,
            origin_lat_milli_degrees=MIN_LAT_MILLI,
            origin_lon_milli_degrees=MIN_LON_MILLI,
            rows=ROWS,
            cols=COLS,
            source_id=source_id,
        )
        cells = rasterise(
            layer, spec, field=field, value_for=value_for, encoding="latin-1"
        )
        (out_dir / filename).write_bytes(write_packed_grid(spec, cells))
        written[filename] = sum(1 for cell in cells if cell)

    (out_dir / "grids.manifest.json").write_text(
        json.dumps(
            {
                "lattice": {
                    "cellMilliDegrees": CELL_MILLI,
                    "originLatMilliDegrees": MIN_LAT_MILLI,
                    "originLonMilliDegrees": MIN_LON_MILLI,
                    "rows": ROWS,
                    "cols": COLS,
                },
                "resolvedCells": written,
                "totalCells": ROWS * COLS,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    return written


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUT_DIR)
    parser.add_argument("--data", type=Path, default=DATA_DIR)
    args = parser.parse_args(argv)

    written = build(out_dir=args.out, data_dir=args.data)
    total = ROWS * COLS
    for name, resolved in written.items():
        size = (args.out / name).stat().st_size
        print(f"{name}: {resolved}/{total} cells resolved, {size / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
