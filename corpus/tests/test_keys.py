"""The cell keys, derived rather than written down twice.

ADR 0022 records the coupling this guards: "If a future ADR changes the four
classes, cells for changed classes are orphaned. The artifact therefore carries a
class-list version and the build derives keys from `SoilTextureLabels.ordered`
rather than a literal, so the breakage is loud."

Since SPEC 0083 the app declares no class list of its own: it labels a result
with the shipped contract's classes. So these tests read `assets/models/spec.json`.
A literal here would satisfy itself and let the corpus drift away from the model
it is keyed to — which is exactly the failure the ADR asked to be made loud.
"""

import pytest

from src.keys import (
    BIOMES,
    CLAY_ACTIVITIES,
    LABELS_PATH,
    LAND_USES,
    UNITS,
    describe_key,
    read_texture_classes,
    substance_keys,
)


def test_the_class_list_is_read_from_the_shipped_contract():
    classes = read_texture_classes()

    assert classes == ["Arenosa", "Media", "Muito Argilosa", "Argilosa"]
    assert LABELS_PATH.parts[-3:] == ("assets", "models", "spec.json")


def test_a_missing_class_list_fails_loudly(tmp_path):
    missing = tmp_path / "spec.json"

    with pytest.raises(FileNotFoundError):
        read_texture_classes(path=missing)


@pytest.mark.parametrize(
    "document",
    ['{"spec_version": 2}', '{"classes": []}', '{"classes": "Arenosa"}', "[]"],
)
def test_a_class_list_that_cannot_be_parsed_fails_loudly(tmp_path, document):
    path = tmp_path / "spec.json"
    path.write_text(document, encoding="utf-8")

    with pytest.raises(ValueError) as excinfo:
        read_texture_classes(path=path)

    assert "classes" in str(excinfo.value)


def test_there_are_twelve_substance_cells():
    # 4 classes x 3 clay-activity families, which is the halving the 2026-09-11
    # re-key bought: 24 cells under the biome key became 12 under this one.
    keys = substance_keys()

    assert len(keys) == 12
    assert len(set(keys)) == 12


def test_a_substance_key_is_class_then_family():
    keys = substance_keys()

    assert "Argilosa|tb_oxidic" in keys
    assert all(key.count("|") == 1 for key in keys)


def test_the_three_clay_activity_families_are_the_designs():
    assert CLAY_ACTIVITIES == ("tb_oxidic", "intermediate", "ta_less_weathered")


def test_the_five_land_uses_are_the_designs():
    assert LAND_USES == (
        "native_vegetation",
        "pasture",
        "annual_crop",
        "perennial_or_forest",
        "exposed_or_degraded",
    )


def test_there_are_twenty_seven_federative_units():
    assert len(UNITS) == 27
    assert len(set(UNITS)) == 27
    assert all(unit.startswith("BR-") and len(unit) == 5 for unit in UNITS)


def test_there_are_six_biomes():
    assert BIOMES == (
        "amazonia",
        "cerrado",
        "mata_atlantica",
        "caatinga",
        "pampa",
        "pantanal",
    )


def test_the_artifact_count_is_forty_four():
    # The number the budget, the review burden and ADR 0022's consequences all
    # quote. The 6-entry biome table is a lookup, not a reviewed artifact.
    assert len(substance_keys()) + len(LAND_USES) + len(UNITS) == 44


def test_every_texture_class_is_described():
    """Every cell the build derives from the contract has a description, so a
    class added to the model fails here rather than reaching the chain as an
    identifier (SPEC 0152)."""
    for key in substance_keys():
        assert describe_key(key).strip()


def test_the_description_names_the_family_in_words():
    """The chain was handed `Argilosa|tb_oxidic` and nothing else, so its
    queries only reordered the identifier and its tip read the family backwards
    (SPEC 0152)."""
    description = describe_key("Argilosa|tb_oxidic")

    assert "textura argilosa" in description
    assert "atividade baixa" in description
    assert "tb_oxidic" not in description
    assert "|" not in description


@pytest.mark.parametrize(
    "key", ["Siltosa|tb_oxidic", "Argilosa|unknown", "Argilosa", "Argilosa|"]
)
def test_an_undescribed_key_fails_loudly(key):
    with pytest.raises(ValueError):
        describe_key(key)
