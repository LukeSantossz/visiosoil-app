"""The six-entry biome-to-Embrapa-unit table of §5.1.

It is a lookup rather than generated guidance, which is why ADR 0022 counts 44
reviewed artifacts and not 50: this table is read once with the corpus and is not
one of them.
"""

import pytest

from src.embrapa_units import UNIT_BY_BIOME, unit_for_biome
from src.keys import BIOMES


def test_every_biome_has_an_entry():
    assert set(UNIT_BY_BIOME) == set(BIOMES)


def test_the_four_biome_named_units_are_the_ones_adr_0022_names():
    assert unit_for_biome("cerrado")["name"] == "Embrapa Cerrados"
    assert unit_for_biome("caatinga")["name"] == "Embrapa Semiárido"
    assert unit_for_biome("pantanal")["name"] == "Embrapa Pantanal"
    assert unit_for_biome("pampa")["name"] == "Embrapa Clima Temperado"


def test_the_amazon_resolves_to_the_eastern_unit_and_says_a_second_exists():
    entry = unit_for_biome("amazonia")

    assert entry["name"] == "Embrapa Amazônia Oriental"
    assert "Ocidental" in entry["caveat"]


def test_the_atlantic_forest_entry_states_that_no_unit_is_named_for_it():
    # The honest gap: ADR 0022 says Embrapa's units are "biome-shaped" and names
    # four. Mata Atlântica is not one of them, so the entry says which unit it
    # points at and why, rather than implying a match that does not exist.
    entry = unit_for_biome("mata_atlantica")

    assert entry["caveat"]
    assert "nenhuma unidade" in entry["caveat"].lower()


def test_every_entry_carries_a_city_and_a_state():
    for biome, entry in UNIT_BY_BIOME.items():
        assert entry["city"], biome
        assert entry["unit"].startswith("BR-"), biome
        assert len(entry["unit"]) == 5, biome


def test_an_unknown_biome_resolves_to_null_rather_than_guessing():
    assert unit_for_biome("tundra") is None
    assert unit_for_biome(None) is None


def test_a_caveat_is_present_only_where_there_is_something_to_say():
    plain = unit_for_biome("cerrado")

    assert plain["caveat"] == ""
