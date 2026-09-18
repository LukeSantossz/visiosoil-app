"""SiBCS class name to clay-activity family.

The mapping is **order first, qualifier second**, and the order matters because
Ta/Tb appears in a great-group name only where it *differentiates*. Where the
order already implies the activity, the name carries no qualifier at all: a
Latossolo is low-activity by the definition of its own B horizon, so a search for
"Tb" in its name finds nothing and would resolve it wrongly to unknown — in the
most common order of the Cerrado, which is where the `Argilosa|tb_oxidic` cell
lives.
"""

from src.clay_activity import family_for_soil_class


def test_a_latossolo_is_low_activity_without_carrying_the_qualifier():
    assert family_for_soil_class("LATOSSOLO VERMELHO Distrófico") == "tb_oxidic"
    assert family_for_soil_class("Latossolo Amarelo Distrocoeso") == "tb_oxidic"


def test_a_nitossolo_is_low_activity_by_its_definition():
    assert family_for_soil_class("NITOSSOLO VERMELHO Eutroférrico") == "tb_oxidic"


def test_an_explicit_tb_qualifier_is_read():
    assert (
        family_for_soil_class("ARGISSOLO VERMELHO-AMARELO Tb Distrófico")
        == "tb_oxidic"
    )


def test_an_explicit_ta_qualifier_is_read():
    assert (
        family_for_soil_class("ARGISSOLO VERMELHO Ta Eutrófico")
        == "ta_less_weathered"
    )
    assert family_for_soil_class("LUVISSOLO CRÔMICO Órtico") == "ta_less_weathered"


def test_the_qualifier_outranks_the_order_default():
    # An order whose default is low activity but whose name says Ta is Ta. The
    # qualifier is the measurement; the default is an inference from the order.
    assert (
        family_for_soil_class("CAMBISSOLO HÁPLICO Ta Eutrófico")
        == "ta_less_weathered"
    )
    assert (
        family_for_soil_class("CAMBISSOLO HÁPLICO Tb Distrófico") == "tb_oxidic"
    )


def test_an_order_that_settles_neither_resolves_to_null():
    # §5.2: a null family is valid and not fatal — the substance layer answers
    # generically and the response says so.
    assert family_for_soil_class("NEOSSOLO QUARTZARÊNICO Órtico") is None
    assert family_for_soil_class("ORGANOSSOLO HÁPLICO Sáprico") is None


def test_an_unknown_class_resolves_to_null_rather_than_guessing():
    assert family_for_soil_class("SOLO DESCONHECIDO") is None
    assert family_for_soil_class("") is None
    assert family_for_soil_class(None) is None


def test_accents_and_case_do_not_change_the_answer():
    assert family_for_soil_class("latossolo vermelho") == "tb_oxidic"
    assert family_for_soil_class("LUVISSOLO CROMICO") == "ta_less_weathered"


def test_a_qualifier_is_a_token_not_a_substring():
    """The name here is constructed, and deliberately so.

    No SiBCS great-group name in the map happens to contain "ta" or "tb" inside a
    word today, so a substring match would pass every real sample and fail the
    first time the vocabulary grew. The guard is written against the hazard, not
    against the sample that would currently expose it.
    """
    assert family_for_soil_class("CAMBISSOLO HÁPLICO Tabular") == "intermediate"
    assert family_for_soil_class("CAMBISSOLO HÁPLICO Otbico") == "intermediate"
    # And the real qualifier, standing alone, is still read.
    assert family_for_soil_class("CAMBISSOLO HÁPLICO Ta") == "ta_less_weathered"


def test_a_planossolo_defaults_to_intermediate_without_a_qualifier():
    assert family_for_soil_class("PLANOSSOLO NÁTRICO Órtico") == "intermediate"


def test_every_family_it_can_return_is_one_the_corpus_keys_by():
    from src.keys import CLAY_ACTIVITIES

    samples = [
        "LATOSSOLO VERMELHO",
        "ARGISSOLO VERMELHO Ta Eutrófico",
        "PLANOSSOLO HÁPLICO",
        "NEOSSOLO LITÓLICO",
    ]
    for name in samples:
        family = family_for_soil_class(name)
        assert family is None or family in CLAY_ACTIVITIES


# --- What the real IBGE legend turned out to look like -----------------------
#
# The attribute table of `Solos_5000` was opened on 2026-09-17 and it settles the
# question §15.3 left open, though not the way the metadata suggested. The legend
# carries clay activity **spelled out** — "Argila de atividade alta" / "baixa" —
# and never as the Ta/Tb notation. A guard written against Ta/Tb alone finds
# nothing in the whole country.


def test_the_spelled_out_qualifier_is_read():
    assert (
        family_for_soil_class("Cambissolo háplico Argila de atividade alta Eutrófico")
        == "ta_less_weathered"
    )
    assert (
        family_for_soil_class("Gleissolo háplico Argila de atividade baixa Distrófico")
        == "tb_oxidic"
    )


def test_the_spelled_out_qualifier_outranks_the_order_default():
    # Neossolo settles nothing on its own, but this one says so in words.
    assert (
        family_for_soil_class("Neossolo flúvico Argila de atividade baixa Eutrófico")
        == "tb_oxidic"
    )
    assert (
        family_for_soil_class("Neossolo flúvico Argila de atividade alta Eutrófico")
        == "ta_less_weathered"
    )


def test_the_legacy_spelling_argilossolo_is_the_same_order_as_argissolo():
    # The legend carries both: five entries as "Argilossolo", the pre-SiBCS
    # spelling, and one as "Argissolo". Keying on the modern spelling alone would
    # drop five sixths of them.
    assert family_for_soil_class("Argilossolo vermelho Distrófico") == "tb_oxidic"
    assert family_for_soil_class("Argissolo acinzentado Distrófico") == "tb_oxidic"


def test_an_alissolo_is_high_activity():
    assert family_for_soil_class("Alissolo crômico Argilúvico") == "ta_less_weathered"


def test_non_soil_map_units_resolve_to_null():
    for name in (
        "Afloramentos de rochas",
        "Dunas",
        "Massa Dagua Continental",
        "Massa Dagua Costeira - Mar Territorial, 12 milhas",
    ):
        assert family_for_soil_class(name) is None, name


def test_a_bare_map_symbol_left_in_the_description_resolves_to_null():
    # "PVA Eutrófico" is a raw symbol that escaped into the description field.
    # Guessing from it would be inventing a classification.
    assert family_for_soil_class("PVA Eutrófico") is None


def test_every_legend_entry_resolves_without_raising():
    """The whole legend, exercised.

    Sixty-nine entries is small enough to check exhaustively, and doing so is
    what turns "the mapping looks right" into "the mapping covers the file".
    """
    import shapefile
    from pathlib import Path

    layer = Path(__file__).resolve().parent.parent / "data" / "solos" / "Solos_5000"
    if not layer.with_suffix(".shp").exists():
        import pytest as _pytest

        _pytest.skip("source data is not downloaded; see corpus/README.md")

    reader = shapefile.Reader(str(layer), encoding="latin-1")
    fields = [f[0] for f in reader.fields[1:]]
    column = fields.index("DSC_COMPON")
    names = {str(record[column]) for record in reader.records()}

    for name in names:
        family_for_soil_class(name)
