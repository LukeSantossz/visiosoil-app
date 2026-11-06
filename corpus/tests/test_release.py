"""The corpus release: one build's substance cells and both grids, checked and
written where the app reads them (SPEC 0227)."""

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from src.build_grids import BIOME_KIND, CLAY_KIND
from src.grids import GridSpec, write_packed_grid
from src.keys import BIOMES, CLAY_ACTIVITIES, generic_keys
from src.pipeline import ABSTENTION_DISCLAIMER, SUBSTANCE_DISCLAIMER
from src.cell import validate_cell
from src.release import (
    REJECTED_TIPS,
    ReleaseError,
    default_by_biome,
    read_rejected_tips,
    release,
)

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


FAMILY_KEY = "Argilosa|tb_oxidic"
"""The one family-specific cell the fixture's sources directory has a manifest for."""


def slug(key):
    return key.replace("|", "__").replace(" ", "-")


def write_source_manifest(directory, key):
    (directory / f"{slug(key)}.manifest.json").write_text(
        json.dumps({"cell": key, "sources": []}), encoding="utf-8"
    )


@pytest.fixture
def build(tmp_path):
    cells = tmp_path / "cells"
    grids = tmp_path / "grids"
    out = tmp_path / "out"
    sources = tmp_path / "sources"
    for directory in (cells, grids, sources):
        directory.mkdir()
    for key in [*generic_keys(), FAMILY_KEY]:
        write_source_manifest(sources, key)
        write_cell(cells, key, grounded())
    write_grids(grids)
    return cells, grids, out, sources


def run(build, **overrides):
    cells, grids, out, sources = build
    return release(
        cells_dir=cells,
        grids_dir=grids,
        sources_dir=sources,
        out_dir=out,
        version=overrides.get("version", "2026.10.28"),
        built_at=BUILT_AT,
        rejected_tips=overrides.get("rejected_tips", REJECTED_TIPS),
    )


def written(build, **overrides):
    run(build, **overrides)
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


def test_every_expected_key_is_released(build):
    """The generic cells, then the family cells that have a manifest (SPEC 0234)."""
    assert list(written(build)["substance"]) == [*generic_keys(), FAMILY_KEY]


def test_release_requires_every_generic_cell(build):
    cells = build[0]
    for path in cells.glob("Media__generic.*"):
        path.unlink()
    with pytest.raises(ReleaseError, match="Media\\|generic"):
        run(build)


def test_release_refuses_a_family_cell_without_a_manifest(build):
    write_cell(build[0], "Media|intermediate", grounded())
    with pytest.raises(ReleaseError, match="Media\\|intermediate"):
        run(build)


def test_release_requires_a_family_cell_that_has_a_manifest(build):
    write_source_manifest(build[3], "Arenosa|ta_less_weathered")
    with pytest.raises(ReleaseError, match="Arenosa\\|ta_less_weathered"):
        run(build)


def test_an_extra_key_is_refused(build):
    write_cell(build[0], "Siltosa|generic", grounded())
    with pytest.raises(ReleaseError, match="Siltosa\\|generic"):
        run(build)


def test_a_key_two_manifests_name_is_refused(build):
    # A stale copy under another file name must not replace the cell.
    cells = build[0]
    for suffix in ("cell", "manifest"):
        original = cells / f"Arenosa__generic.{suffix}.json"
        copy = cells / f"Arenosa__generic.backup.{suffix}.json"
        copy.write_text(original.read_text(encoding="utf-8"), encoding="utf-8")
    with pytest.raises(ReleaseError, match="Arenosa\\|generic"):
        run(build)


def test_cells_from_two_models_are_refused(build):
    write_cell(build[0], "Arenosa|generic", grounded(), model="llama3.1:8b")
    with pytest.raises(ReleaseError, match="model"):
        run(build)


def test_cells_from_two_prompt_versions_are_refused(build):
    write_cell(build[0], "Arenosa|generic", grounded(), generate="5")
    with pytest.raises(ReleaseError, match="prompt"):
        run(build)


def test_a_citation_outside_its_sources_is_refused(build):
    cell = grounded()
    cell["tips"][0]["citations"] = [3]
    write_cell(build[0], "Arenosa|generic", cell)
    with pytest.raises(ReleaseError, match="Arenosa\\|generic"):
        run(build)


def test_an_empty_disclaimer_is_refused(build):
    cell = grounded()
    cell["disclaimer"] = " "
    write_cell(build[0], "Arenosa|generic", cell)
    with pytest.raises(ReleaseError, match="Arenosa\\|generic"):
        run(build)


def test_nothing_is_written_when_the_release_is_refused(build):
    write_cell(build[0], "Arenosa|generic", grounded(), model="llama3.1:8b")
    with pytest.raises(ReleaseError):
        run(build)
    assert not build[2].exists() or not any(build[2].iterdir())


def test_an_abstained_cell_is_released_as_it_is(build):
    write_cell(build[0], "Arenosa|generic", abstained())
    assert written(build)["substance"]["Arenosa|generic"] == abstained()


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


# The rejection list (SPEC 0262).


def rejection(phrase, *, found_in="Arenosa|generic"):
    return {
        "phrase": phrase,
        "foundIn": found_in,
        "reason": "QA rejected it.",
        "reference": "https://example.org/review",
    }


def write_rejections(tmp_path, entries):
    path = tmp_path / "rejected_tips.json"
    path.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
    return path


def cell_with(*texts):
    cell = grounded()
    cell["tips"] = [{"text": text, "citations": [0]} for text in texts]
    return cell


def test_a_rejected_tip_is_dropped_in_any_cell_and_any_casing(build, tmp_path, capsys):
    write_cell(
        build[0],
        "Media|generic",
        cell_with("Uma dica boa.", "O solo NÃO significa   baixa retenção, e ponto."),
    )
    rejected = write_rejections(
        tmp_path, [rejection("não significa baixa retenção", found_in="Arenosa|generic")]
    )

    corpus = written(build, rejected_tips=rejected)

    assert corpus["substance"]["Media|generic"]["tips"] == [
        {"text": "Uma dica boa.", "citations": [0]}
    ]
    printed = capsys.readouterr().out
    assert "Media|generic" in printed
    assert "não significa baixa retenção" in printed


def test_a_cell_left_without_tips_is_released_as_the_abstention(build, tmp_path):
    cell = cell_with("Uma afirmação rejeitada.")
    write_cell(build[0], "Argilosa|generic", cell)
    rejected = write_rejections(tmp_path, [rejection("afirmação rejeitada")])

    released = written(build, rejected_tips=rejected)["substance"]["Argilosa|generic"]

    assert released["status"] == "abstained"
    assert released["tips"] == []
    assert released["disclaimer"] == ABSTENTION_DISCLAIMER
    assert released["sources"] == cell["sources"]
    assert released["limitations"] == cell["limitations"]
    validate_cell(released, source_count=len(released["sources"]))


def test_tips_that_match_nothing_are_released_unchanged(build, tmp_path):
    cell = grounded()
    cell["sources"].append(dict(cell["sources"][0], url="https://example.org/1"))
    cell["tips"] = [
        {"text": "Primeira dica.", "citations": [1]},
        {"text": "Segunda dica.", "citations": [0, 1]},
    ]
    write_cell(build[0], "Arenosa|generic", cell)
    rejected = write_rejections(tmp_path, [rejection("nada disso aparece")])

    assert written(build, rejected_tips=rejected)["substance"]["Arenosa|generic"] == cell


def test_dropping_a_tip_keeps_the_citations_of_the_rest(build, tmp_path):
    cell = grounded()
    cell["sources"].append(dict(cell["sources"][0], url="https://example.org/1"))
    cell["tips"] = [
        {"text": "Dica rejeitada.", "citations": [0]},
        {"text": "Dica mantida.", "citations": [1]},
    ]
    write_cell(build[0], "Arenosa|generic", cell)
    rejected = write_rejections(tmp_path, [rejection("dica rejeitada")])

    released = written(build, rejected_tips=rejected)["substance"]["Arenosa|generic"]

    assert released["status"] == "grounded"
    assert released["tips"] == [{"text": "Dica mantida.", "citations": [1]}]
    assert released["sources"] == cell["sources"]


@pytest.mark.parametrize(
    "entries, cause",
    [
        ({"phrase": "x"}, "array"),
        ([dict(rejection("x"), phrase=" ")], "phrase"),
        ([{k: v for k, v in rejection("x").items() if k != "reason"}], "reason"),
        ([dict(rejection("x"), reference="")], "reference"),
        ([dict(rejection("x"), phrase=3)], "phrase"),
        (["x"], "entry 0"),
    ],
)
def test_a_malformed_rejection_list_is_refused(build, tmp_path, entries, cause):
    rejected = write_rejections(tmp_path, entries)
    with pytest.raises(ReleaseError, match=cause):
        run(build, rejected_tips=rejected)
    assert not build[2].exists() or not any(build[2].iterdir())


def test_a_missing_rejection_list_is_refused(build, tmp_path):
    with pytest.raises(ReleaseError, match="rejected_tips.json"):
        run(build, rejected_tips=tmp_path / "rejected_tips.json")


def test_the_shipped_list_holds_the_known_rejections():
    entries = read_rejected_tips(REJECTED_TIPS)
    by_reference = {}
    for entry in entries:
        by_reference.setdefault(entry["reference"], []).append(entry["phrase"])

    known = [
        "O solo arenoso não necessariamente significa baixo teor de argila.",
        "A textura arenosa do solo não implica em baixa retenção de água",
        "A textura argilosa não significa que o solo é mais propenso a formação "
        "de agregados",
        "O solo argiloso não significa que o potássio não-trocável é "
        "predominantemente indisponível para as plantas.",
    ]
    phrases = [entry["phrase"] for entry in entries]
    for text in known:
        assert any(
            " ".join(phrase.lower().split()) in " ".join(text.lower().split())
            for phrase in phrases
        ), text
    assert any("pull/457" in reference for reference in by_reference)
    assert any("pull/473" in reference for reference in by_reference)
    assert any("0261" in reference for reference in by_reference)
