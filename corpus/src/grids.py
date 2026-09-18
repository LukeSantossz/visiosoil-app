"""Rasterising a shapefile into the packed grid the app reads.

The format is a contract between two languages: this writer produces it and the
app's `PackedGrid.parse` (`lib/core/services/region/grid_site_resolver.dart`)
consumes it. `tests/test_grids.py` asserts the bytes against the committed Dart
fixture, because a contract tested on one side only is a contract that drifts —
and a one-byte disagreement would show as wrong guidance rather than as an error.

Sampling is at the **cell centre**, not by area majority. At 0.1° a cell is
roughly 11 km across, and the source maps are generalised at national scale, so a
majority rule would spend effort resolving boundaries the source does not
actually know. §5.2 already accepts that error is confined to transition bands.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import shapefile

MAGIC = b"VSG1"
FORMAT_VERSION = 1


class RasterisationError(Exception):
    """A grid that cannot be built, named rather than silently degraded.

    A grid is a build product read by every lookup in the country, so a defect
    here must stop the build: a grid that quietly resolves to zero would
    downgrade every answer without anyone noticing.
    """


@dataclass(frozen=True)
class GridSpec:
    """The lattice a shapefile is sampled onto, and what the artifact records."""

    kind: int
    cell_milli_degrees: int
    origin_lat_milli_degrees: int
    origin_lon_milli_degrees: int
    rows: int
    cols: int
    source_id: str

    def centre(self, row: int, col: int) -> tuple[float, float]:
        """The latitude and longitude sampled for a cell."""
        half = self.cell_milli_degrees / 2
        lat = (self.origin_lat_milli_degrees + row * self.cell_milli_degrees + half)
        lon = (self.origin_lon_milli_degrees + col * self.cell_milli_degrees + half)
        return lat / 1000, lon / 1000


def _contains(rings: list[list[list[float]]], x: float, y: float) -> bool:
    """Ray casting over a polygon's rings.

    Written out rather than imported: the alternative readers pull GDAL, and the
    only predicate this module needs is point-in-polygon over axis-agnostic
    rings.
    """
    inside = False
    for ring in rings:
        for index in range(len(ring)):
            x1, y1 = ring[index][0], ring[index][1]
            x2, y2 = ring[index - 1][0], ring[index - 1][1]
            if (y1 > y) != (y2 > y):
                crossing = x1 + (y - y1) / (y2 - y1) * (x2 - x1)
                if x < crossing:
                    inside = not inside
    return inside


def _rings(shape) -> list[list[list[float]]]:
    parts = list(shape.parts) + [len(shape.points)]
    return [
        [list(point) for point in shape.points[parts[i] : parts[i + 1]]]
        for i in range(len(parts) - 1)
    ]


def rasterise(
    path: Path,
    spec: GridSpec,
    *,
    field: str,
    value_for: Callable[[str], int],
    encoding: str = "utf-8",
) -> list[int]:
    """Samples [path] onto [spec]'s lattice, one byte per cell.

    [encoding] is the source's, and it is stated rather than sniffed.

    [value_for] turns an attribute value into the byte to store — 0 for
    unresolved, otherwise the one-based index into the enumeration the grid's
    kind names. Keeping it a parameter is what lets the clay-activity mapping
    live in `clay_activity.py` and be tested on its own.
    """
    # The encoding is a property of the source, not a default worth guessing:
    # pyshp assumes utf-8 and the IBGE files are latin-1, which surfaced as a
    # `UnicodeDecodeError` on the first accented legend entry of the real build.
    reader = shapefile.Reader(str(path), encoding=encoding)
    names = [f[0] for f in reader.fields[1:]]
    if field not in names:
        raise RasterisationError(
            f"{path} has no attribute {field!r}; it carries {names}"
        )
    column = names.index(field)

    cells = [0] * (spec.rows * spec.cols)

    # Iterated by shape rather than by cell, and clipped to each shape's own
    # bounding box.
    #
    # Cell-major was the obvious shape and it does not survive real data: 160 000
    # cells against 2 959 polygons is every cell tested against every polygon,
    # which is billions of point-in-polygon tests in pure Python. A polygon's
    # bounding box, which the shapefile already carries, bounds the cells it can
    # possibly cover — and most cover a handful.
    #
    # First-in-file still wins, because a cell is written only while it is still
    # unresolved. That keeps the semantics of the cell-major version it replaces.
    shapes = reader.shapes()
    records = reader.records()
    if len(shapes) != len(records):
        # `zip` would truncate to the shorter of the two and still produce a
        # well-formed grid. The polygons it dropped would read as unresolved
        # cells, which is indistinguishable from land the legend genuinely does
        # not classify — wrong guidance rather than a failed build.
        raise RasterisationError(
            f"{path} has {len(shapes)} shape(s) but {len(records)} record(s); "
            f"the SHP and DBF disagree and the grid would silently omit the "
            f"difference"
        )

    for shape, record in zip(shapes, records):
        value = value_for(str(record[column]))
        if not isinstance(value, int) or not 0 <= value <= 255:
            raise RasterisationError(
                f"value_for returned {value!r}, which is not a byte; the grid "
                f"stores one byte per cell"
            )
        if not value:
            continue

        min_lon, min_lat, max_lon, max_lat = shape.bbox
        first_row, last_row = _cell_range(
            min_lat, max_lat, spec.origin_lat_milli_degrees,
            spec.cell_milli_degrees, spec.rows,
        )
        first_col, last_col = _cell_range(
            min_lon, max_lon, spec.origin_lon_milli_degrees,
            spec.cell_milli_degrees, spec.cols,
        )
        if first_row > last_row or first_col > last_col:
            continue

        rings = _rings(shape)
        for row in range(first_row, last_row + 1):
            for col in range(first_col, last_col + 1):
                index = row * spec.cols + col
                if cells[index]:
                    continue
                lat, lon = spec.centre(row, col)
                if _contains(rings, lon, lat):
                    cells[index] = value
    return cells


def _cell_range(
    low: float, high: float, origin_milli: int, cell_milli: int, count: int
) -> tuple[int, int]:
    """The inclusive index range a span covers, clipped to the lattice."""
    first = int((low * 1000 - origin_milli) // cell_milli)
    last = int((high * 1000 - origin_milli) // cell_milli)
    return max(first, 0), min(last, count - 1)


def write_packed_grid(spec: GridSpec, cells: list[int]) -> bytes:
    """The artifact bytes, in the layout `PackedGrid` documents and parses."""
    if len(cells) != spec.rows * spec.cols:
        raise RasterisationError(
            f"{len(cells)} cells for a {spec.rows} x {spec.cols} lattice"
        )
    source = spec.source_id.encode("utf-8")
    if len(source) > 255:
        raise RasterisationError("source id does not fit in one byte of length")
    header = MAGIC + struct.pack(
        ">BBHiiHHB",
        FORMAT_VERSION,
        spec.kind,
        spec.cell_milli_degrees,
        spec.origin_lat_milli_degrees,
        spec.origin_lon_milli_degrees,
        spec.rows,
        spec.cols,
        len(source),
    )
    return header + source + bytes(cells)
