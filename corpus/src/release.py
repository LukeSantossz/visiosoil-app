"""The corpus release: one build's substance cells and both grids, written where
the app reads them (SPEC 0227).

The probe writes a cell and its run manifest to `corpus/out/`, and `build_grids`
writes the two lattices. This is the one step that moves them into
`assets/corpus/`, so it is where the contract is checked a last time: a key
missing or extra, cells from two builds, a cell the app's reader would reject,
or a grid that is not the one its name says. Every refusal names its cause, and
nothing is written unless everything passes.

The Developer decided on 2026-10-28 to publish these cells without B4's named
human review. The release records that in the artifact as `humanReview: false`.

    python -m src.release --cells out/ --grids out/ --version 2026.10.28
"""

from __future__ import annotations

import argparse
import json
import struct
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from src.build_grids import BIOME_KIND, CLAY_KIND
from src.cell import CellValidationError, validate_cell
from src.grids import MAGIC
from src.keys import BIOMES, CLAY_ACTIVITIES, substance_keys
from src.pipeline import SUBSTANCE_DISCLAIMER

DEFAULT_OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "corpus"
CLASS_LIST_VERSION = "v1-four-class"
"""The class list the substance keys are drawn from (research-agent.md §6.1)."""

GRIDS = (("clay-activity-grid.bin", CLAY_KIND), ("biome-grid.bin", BIOME_KIND))
_HEADER = struct.Struct(">BBHiiHHB")


class ReleaseError(Exception):
    """A release that would ship something the app cannot trust, named."""


def default_by_biome(clay: bytes | list[int], biome: bytes | list[int]) -> dict[str, str]:
    """Each biome's most common clay-activity family over its resolved cells.

    A tie goes to the earlier family in `CLAY_ACTIVITIES`, and a biome with no
    cell where both grids resolve gets no default.
    """
    counts: dict[str, Counter[int]] = {}
    for family, place in zip(clay, biome):
        if family and place:
            counts.setdefault(BIOMES[place - 1], Counter())[family] += 1
    return {
        name: CLAY_ACTIVITIES[
            max(tally, key=lambda family: (tally[family], -family)) - 1
        ]
        for name in BIOMES
        if (tally := counts.get(name))
    }


def _read_grid(path: Path, kind: int) -> tuple[bytes, tuple[int, ...], bytes]:
    """The file's bytes, its lattice, and its cells."""
    if not path.is_file():
        raise ReleaseError(f"{path.name} is missing from the grids directory")
    data = path.read_bytes()
    header_end = len(MAGIC) + _HEADER.size
    if data[: len(MAGIC)] != MAGIC or len(data) < header_end:
        raise ReleaseError(f"{path.name} is not a packed grid")
    _, found, *lattice, source_length = _HEADER.unpack(data[len(MAGIC) : header_end])
    if found != kind:
        raise ReleaseError(f"{path.name} holds grid kind {found}, not {kind}")
    cells = data[header_end + source_length :]
    rows, cols = lattice[-2:]
    if len(cells) != rows * cols:
        raise ReleaseError(f"{path.name} holds {len(cells)} cells, not {rows * cols}")
    return data, tuple(lattice), cells


def _read_cells(cells_dir: Path) -> tuple[dict[str, dict[str, Any]], str]:
    """Every cell by its manifest's key, and the one model that built them."""
    cells: dict[str, dict[str, Any]] = {}
    builds: set[tuple[str, str]] = set()
    for manifest_path in sorted(Path(cells_dir).glob("*.manifest.json")):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        key = manifest["key"]
        cell_path = manifest_path.with_name(
            manifest_path.name.replace(".manifest.json", ".cell.json")
        )
        if not cell_path.is_file():
            raise ReleaseError(f"{key} has a run manifest and no cell")
        cell = json.loads(cell_path.read_text(encoding="utf-8"))
        sources = cell.get("sources")
        try:
            if not isinstance(sources, list):
                raise CellValidationError("cell sources must be a list")
            validate_cell(cell, source_count=len(sources))
        except CellValidationError as error:
            raise ReleaseError(f"{key}: {error}") from error
        cells[key] = cell
        builds.add(
            (manifest["model"], json.dumps(manifest["promptVersions"], sort_keys=True))
        )

    expected = substance_keys()
    missing = [key for key in expected if key not in cells]
    extra = sorted(key for key in cells if key not in expected)
    if missing:
        raise ReleaseError(f"no cell for {', '.join(missing)}")
    if extra:
        raise ReleaseError(f"cells outside the substance keys: {', '.join(extra)}")
    models = {model for model, _ in builds}
    if len(models) > 1:
        raise ReleaseError(f"cells from more than one model: {sorted(models)}")
    if len(builds) > 1:
        raise ReleaseError("cells built under more than one set of prompt versions")
    return {key: cells[key] for key in expected}, models.pop()


def _timestamp(instant: datetime) -> str:
    utc = instant.astimezone(timezone.utc)
    return utc.strftime("%Y-%m-%dT%H:%M:%S.") + f"{utc.microsecond // 1000:03d}Z"


def release(
    *,
    cells_dir: Path,
    grids_dir: Path,
    out_dir: Path = DEFAULT_OUT_DIR,
    version: str,
    built_at: datetime,
) -> dict[str, Any]:
    """Checks the build and writes `corpus.json` and both grids into [out_dir]."""
    cells, model = _read_cells(cells_dir)
    grids = [
        (name, *_read_grid(Path(grids_dir) / name, kind)) for name, kind in GRIDS
    ]
    (_, _, clay_lattice, clay), (_, _, biome_lattice, biome) = grids
    if clay_lattice != biome_lattice:
        raise ReleaseError("the two grids are on different lattices")

    corpus = {
        "corpusVersion": version,
        "classListVersion": CLASS_LIST_VERSION,
        "model": model,
        "builtAt": _timestamp(built_at),
        "humanReview": False,
        "disclaimer": SUBSTANCE_DISCLAIMER,
        "clayActivityDefaultByBiome": default_by_biome(clay, biome),
        "substance": cells,
    }

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "corpus.json").write_text(
        json.dumps(corpus, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for name, data, _, _ in grids:
        (out / name).write_bytes(data)
    return corpus


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cells", required=True, type=Path)
    parser.add_argument("--grids", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args(argv)
    corpus = release(
        cells_dir=args.cells,
        grids_dir=args.grids,
        out_dir=args.out,
        version=args.version,
        built_at=datetime.now(timezone.utc),
    )
    statuses = Counter(cell["status"] for cell in corpus["substance"].values())
    print(f"released {args.out}: {dict(statuses)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
