"""The cell keys, derived rather than written down twice.

ADR 0022 records the coupling this guards: "If a future ADR changes the four
classes, cells for changed classes are orphaned. The artifact therefore carries a
class-list version and the build derives keys from `SoilTextureLabels.ordered`
rather than a literal, so the breakage is loud."

So these tests read the app's Dart file. A literal here would satisfy itself and
let the corpus drift away from the model it is keyed to — which is exactly the
failure the ADR asked to be made loud.
"""

import pytest

from src.keys import (
    BIOMES,
    CLAY_ACTIVITIES,
    LAND_USES,
    UNITS,
    read_texture_classes,
    substance_keys,
)


def test_the_class_list_is_read_from_the_app_not_repeated_here():
    classes = read_texture_classes()

    assert classes == ["Arenosa", "Media", "Muito Argilosa", "Argilosa"]


def test_a_missing_class_list_fails_loudly(tmp_path):
    missing = tmp_path / "soil_texture_labels.dart"

    with pytest.raises(FileNotFoundError):
        read_texture_classes(path=missing)


def test_a_class_list_that_cannot_be_parsed_fails_loudly(tmp_path):
    path = tmp_path / "soil_texture_labels.dart"
    path.write_text("class SoilTextureLabels {}", encoding="utf-8")

    with pytest.raises(ValueError) as excinfo:
        read_texture_classes(path=path)

    assert "ordered" in str(excinfo.value)


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
