"""Rasterising a shapefile into the packed grid the app reads.

The strongest test here is the last one: the bytes this writer produces for the
fixture's inputs must equal the bytes the **Dart** fixture builder produced and
the app's `PackedGrid.parse` reads. The format is a contract between two
languages, and a contract tested on only one side is a contract that drifts.
"""

import struct
from pathlib import Path

import pytest
import shapefile

from src.grids import GridSpec, RasterisationError, rasterise, write_packed_grid

FIXTURE_GRIDS = (
    Path(__file__).resolve().parent.parent.parent
    / "test"
    / "fixtures"
    / "corpus"
    / "grids"
)


def square(writer, minx, miny, maxx, maxy, value):
    """One axis-aligned polygon carrying an attribute."""
    writer.poly([[[minx, miny], [minx, maxy], [maxx, maxy], [maxx, miny], [minx, miny]]])
    writer.record(value)


def build_shapefile(tmp_path, polygons, field="classe"):
    path = tmp_path / "layer"
    with shapefile.Writer(str(path)) as writer:
        writer.field(field, "C", size=80)
        for minx, miny, maxx, maxy, value in polygons:
            square(writer, minx, miny, maxx, maxy, value)
    return path


def spec(**overrides):
    base = dict(
        kind=1,
        cell_milli_degrees=100,
        origin_lat_milli_degrees=-23000,
        origin_lon_milli_degrees=-47000,
        rows=3,
        cols=3,
        source_id="fixture-soil-map",
    )
    base.update(overrides)
    return GridSpec(**base)


def test_a_polygon_covering_a_cell_sets_its_value(tmp_path):
    # One square covering the whole 3x3 lattice.
    path = build_shapefile(tmp_path, [(-47.0, -23.0, -46.7, -22.7, "LATOSSOLO VERMELHO")])

    cells = rasterise(
        path, spec(), field="classe", value_for=lambda name: 1 if name else 0
    )

    assert cells == [1] * 9


def test_a_cell_no_polygon_covers_is_unresolved(tmp_path):
    # A square covering only the south-west cell.
    path = build_shapefile(tmp_path, [(-47.0, -23.0, -46.9, -22.9, "LATOSSOLO")])

    cells = rasterise(path, spec(), field="classe", value_for=lambda name: 1)

    assert cells[0] == 1
    assert cells[1:] == [0] * 8


def test_the_sample_point_is_the_cell_centre(tmp_path):
    # A square that covers the centre of cell 0 but not its corners would still
    # set it; one that covers a corner and misses the centre must not.
    corner_only = build_shapefile(
        tmp_path, [(-47.0, -23.0, -46.97, -22.97, "LATOSSOLO")]
    )

    cells = rasterise(corner_only, spec(), field="classe", value_for=lambda n: 1)

    assert cells == [0] * 9


def test_a_value_the_mapping_rejects_is_unresolved(tmp_path):
    path = build_shapefile(tmp_path, [(-47.0, -23.0, -46.7, -22.7, "NEOSSOLO")])

    cells = rasterise(
        path, spec(), field="classe", value_for=lambda name: 0
    )

    assert cells == [0] * 9


def test_a_missing_attribute_field_fails_loudly(tmp_path):
    path = build_shapefile(tmp_path, [(-47.0, -23.0, -46.7, -22.7, "X")])

    with pytest.raises(RasterisationError) as excinfo:
        rasterise(path, spec(), field="inexistente", value_for=lambda n: 1)

    assert "inexistente" in str(excinfo.value)


def test_a_value_outside_one_byte_fails_loudly(tmp_path):
    path = build_shapefile(tmp_path, [(-47.0, -23.0, -46.7, -22.7, "X")])

    with pytest.raises(RasterisationError):
        rasterise(path, spec(), field="classe", value_for=lambda n: 300)


def test_the_header_is_what_the_app_reads():
    payload = write_packed_grid(spec(), [0, 1, 1, 2, 2, 3, 3, 3, 0])

    assert payload[:4] == b"VSG1"
    assert payload[4] == 1  # format version
    assert payload[5] == 1  # kind
    assert struct.unpack(">H", payload[6:8])[0] == 100
    assert struct.unpack(">i", payload[8:12])[0] == -23000
    assert struct.unpack(">i", payload[12:16])[0] == -47000
    assert struct.unpack(">H", payload[16:18])[0] == 3
    assert struct.unpack(">H", payload[18:20])[0] == 3
    assert payload[20] == len(b"fixture-soil-map")


def test_a_payload_that_does_not_match_the_header_fails_loudly():
    with pytest.raises(RasterisationError):
        write_packed_grid(spec(), [0, 1])


def test_the_writer_matches_the_committed_dart_fixture():
    """The cross-language contract, asserted on bytes.

    `test/fixtures/corpus/grids/*.bin` were produced by the Dart-side builder and
    are what `PackedGrid.parse` is tested against. If this writer and that
    builder disagree by one byte, the app reads a grid the build cannot produce —
    and the failure would show as wrong guidance, not as an error.
    """
    clay = write_packed_grid(spec(), [0, 1, 1, 2, 2, 3, 3, 3, 0])
    biome = write_packed_grid(
        spec(kind=2, source_id="fixture-biome-map"),
        [2, 2, 2, 3, 3, 3, 0, 3, 3],
    )

    assert clay == (FIXTURE_GRIDS / "clay-activity-grid.bin").read_bytes()
    assert biome == (FIXTURE_GRIDS / "biome-grid.bin").read_bytes()


def test_a_latin1_shapefile_is_read_when_told_so(tmp_path):
    """The IBGE files are latin-1, and pyshp defaults to utf-8.

    Found by running the real build: the first accented legend entry —
    "Latossolo vermelho Distrófico" — raised `UnicodeDecodeError` and stopped it.
    The encoding is a property of the source, so the caller states it.
    """
    path = tmp_path / "layer"
    with shapefile.Writer(str(path), encoding="latin-1") as writer:
        writer.field("classe", "C", size=80)
        square(writer, -47.0, -23.0, -46.7, -22.7, "Latossolo vermelho Distrófico")

    cells = rasterise(
        path,
        spec(),
        field="classe",
        value_for=lambda name: 1 if "Distrófico" in name else 0,
        encoding="latin-1",
    )

    assert cells == [1] * 9


def test_the_default_encoding_is_utf8(tmp_path):
    path = build_shapefile(tmp_path, [(-47.0, -23.0, -46.7, -22.7, "Distrófico")])

    cells = rasterise(
        path, spec(), field="classe", value_for=lambda n: 1 if "ó" in n else 0
    )

    assert cells == [1] * 9
