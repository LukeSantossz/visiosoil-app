"""The corpus release: one build's substance cells and both grids, checked and
written where the app reads them (SPEC 0227)."""

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from src.build_grids import BIOME_KIND, CLAY_KIND
from src.grids import GridSpec, write_packed_grid
from src.keys import BIOMES, CLAY_ACTIVITIES, substance_keys
from src.pipeline import ABSTENTION_DISCLAIMER, SUBSTANCE_DISCLAIMER
from src.release import ReleaseError, default_by_biome, release

FIXTURE = (
    Path(__file__).resolve().parents[2] / "test" / "fixtures" / "corpus" / "corpus.json"
)
OUT_OF_SCOPE = {"_note", "landUse", "unit", "biome"}
BUILT_AT = datetime(2026, 10, 28, 18, 0, tzinfo=timezone.utc)


def grounded():
    return {
        "status": "grounded",
        "disclaimer": SUBSTANCE_DISCLAIMER,
        "tips": [{"text": "Uma dica.", "citations": [0]}],
        "sources": [
            {
                "title": "Fonte",
                "url": "https://example.org/0",
                "publisher": "Embrapa",
                "tier": 1,
                "accessedAt": "2026-10-28T00:00:00.000Z",
            }
        ],
        "limitations": ["Uma limitação."],
    }


def abstained():
    return {
        "status": "abstained",
        "disclaimer": ABSTENTION_DISCLAIMER,
        "tips": [],
        "sources": [],
        "limitations": [],
    }


def write_cell(directory, key, cell, *, model="qwen2.5:7b", generate="6"):
    slug = key.replace("|", "__").replace(" ", "-")
    (directory / f"{slug}.cell.json").write_text(
        json.dumps(cell, ensure_ascii=False), encoding="utf-8"
    )
    manifest = {
        "key": key,
        "model": model,
        "promptVersions": {"grade": "3", "generate": generate},
    }
    (directory / f"{slug}.manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8"
    )


def spec(kind, *, rows=2, cols=3):
    return GridSpec(
        kind=kind,
        cell_milli_degrees=100,
        origin_lat_milli_degrees=-34000,
        origin_lon_milli_degrees=-74000,
        rows=rows,
        cols=cols,
        source_id=f"test-{kind}",
    )


def write_grids(directory, clay=None, biome=None, *, biome_spec=None):
    # amazonia over tb, tb, ta; cerrado over int, int, unresolved.
    clay = clay if clay is not None else [1, 1, 3, 2, 2, 0]
    biome = biome if biome is not None else [1, 1, 1, 2, 2, 2]
    clay_bytes = write_packed_grid(spec(CLAY_KIND), clay)
    biome_bytes = write_packed_grid(biome_spec or spec(BIOME_KIND), biome)
    (directory / "clay-activity-grid.bin").write_bytes(clay_bytes)
    (directory / "biome-grid.bin").write_bytes(biome_bytes)
    return clay_bytes, biome_bytes


@pytest.fixture
def build(tmp_path):
    cells = tmp_path / "cells"
    grids = tmp_path / "grids"
    out = tmp_path / "out"
    cells.mkdir()
    grids.mkdir()
    for key in substance_keys():
        write_cell(cells, key, grounded())
    write_grids(grids)
    return cells, grids, out


def run(build, **overrides):
    cells, grids, out = build
    return release(
        cells_dir=cells,
        grids_dir=grids,
        out_dir=out,
        version=overrides.get("version", "2026.10.28"),
        built_at=BUILT_AT,
    )


def written(build):
    run(build)
    return json.loads((build[2] / "corpus.json").read_text(encoding="utf-8"))


def test_the_release_writes_the_fixtures_fields(build):
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    corpus = written(build)

    expected = set(fixture) - OUT_OF_SCOPE
    assert expected <= set(corpus)
    for field in expected:
        assert type(corpus[field]) is type(fixture[field]), field
    assert corpus["builtAt"] == "2026-10-28T18:00:00.000Z"
    assert corpus["corpusVersion"] == "2026.10.28"
    assert corpus["classListVersion"] == "v1-four-class"
    assert corpus["model"] == "qwen2.5:7b"
    assert corpus["disclaimer"] == SUBSTANCE_DISCLAIMER

    cell_fields = set().union(*(cell.keys() for cell in fixture["substance"].values()))
    for cell in corpus["substance"].values():
        assert set(cell) <= cell_fields


def test_every_substance_key_is_released(build):
    assert sorted(written(build)["substance"]) == sorted(substance_keys())


def test_a_missing_key_is_refused(build):
    cells = build[0]
    for path in cells.glob("Media__intermediate.*"):
        path.unlink()
    with pytest.raises(ReleaseError, match="Media\\|intermediate"):
        run(build)


def test_an_extra_key_is_refused(build):
    write_cell(build[0], "Siltosa|tb_oxidic", grounded())
    with pytest.raises(ReleaseError, match="Siltosa\\|tb_oxidic"):
        run(build)


def test_a_key_two_manifests_name_is_refused(build):
    # A stale copy under another file name must not replace the cell.
    cells = build[0]
    for suffix in ("cell", "manifest"):
        original = cells / f"Arenosa__tb_oxidic.{suffix}.json"
        copy = cells / f"Arenosa__tb_oxidic.backup.{suffix}.json"
        copy.write_text(original.read_text(encoding="utf-8"), encoding="utf-8")
    with pytest.raises(ReleaseError, match="Arenosa\\|tb_oxidic"):
        run(build)


def test_cells_from_two_models_are_refused(build):
    write_cell(build[0], "Arenosa|tb_oxidic", grounded(), model="llama3.1:8b")
    with pytest.raises(ReleaseError, match="model"):
        run(build)


def test_cells_from_two_prompt_versions_are_refused(build):
    write_cell(build[0], "Arenosa|tb_oxidic", grounded(), generate="5")
    with pytest.raises(ReleaseError, match="prompt"):
        run(build)


def test_a_citation_outside_its_sources_is_refused(build):
    cell = grounded()
    cell["tips"][0]["citations"] = [3]
    write_cell(build[0], "Arenosa|tb_oxidic", cell)
    with pytest.raises(ReleaseError, match="Arenosa\\|tb_oxidic"):
        run(build)


def test_an_empty_disclaimer_is_refused(build):
    cell = grounded()
    cell["disclaimer"] = " "
    write_cell(build[0], "Arenosa|tb_oxidic", cell)
    with pytest.raises(ReleaseError, match="Arenosa\\|tb_oxidic"):
        run(build)


def test_nothing_is_written_when_the_release_is_refused(build):
    write_cell(build[0], "Arenosa|tb_oxidic", grounded(), model="llama3.1:8b")
    with pytest.raises(ReleaseError):
        run(build)
    assert not build[2].exists() or not any(build[2].iterdir())


def test_an_abstained_cell_is_released_as_it_is(build):
    write_cell(build[0], "Arenosa|tb_oxidic", abstained())
    assert written(build)["substance"]["Arenosa|tb_oxidic"] == abstained()


def test_the_grids_are_copied_byte_for_byte(build):
    clay, biome = write_grids(build[1])
    run(build)
    assert (build[2] / "clay-activity-grid.bin").read_bytes() == clay
    assert (build[2] / "biome-grid.bin").read_bytes() == biome


def test_a_grid_with_another_magic_is_refused(build):
    path = build[1] / "biome-grid.bin"
    path.write_bytes(b"XXXX" + path.read_bytes()[4:])
    with pytest.raises(ReleaseError, match="biome-grid.bin"):
        run(build)


def test_grids_of_swapped_kinds_are_refused(build):
    grids = build[1]
    clay = (grids / "clay-activity-grid.bin").read_bytes()
    biome = (grids / "biome-grid.bin").read_bytes()
    (grids / "clay-activity-grid.bin").write_bytes(biome)
    (grids / "biome-grid.bin").write_bytes(clay)
    with pytest.raises(ReleaseError, match="kind"):
        run(build)


def test_grids_on_different_lattices_are_refused(build):
    write_grids(
        build[1], biome=[1] * 9, biome_spec=spec(BIOME_KIND, rows=3, cols=3)
    )
    with pytest.raises(ReleaseError, match="lattice"):
        run(build)


def test_the_biome_default_is_the_most_common_family(build):
    defaults = written(build)["clayActivityDefaultByBiome"]
    assert defaults == {"amazonia": "tb_oxidic", "cerrado": "intermediate"}


def test_a_tie_goes_to_the_earlier_family():
    clay = [3, 2, 1, 1]
    biome = [1, 1, 2, 2]
    assert default_by_biome(clay, biome)["amazonia"] == "intermediate"
    assert CLAY_ACTIVITIES.index("intermediate") < CLAY_ACTIVITIES.index(
        "ta_less_weathered"
    )


def test_a_biome_with_no_resolved_cell_gets_no_default():
    defaults = default_by_biome([0, 0, 1], [3, 3, 1])
    assert BIOMES[2] not in defaults
    assert defaults == {"amazonia": "tb_oxidic"}


def test_the_release_says_no_person_reviewed_it(build):
    assert written(build)["humanReview"] is False
