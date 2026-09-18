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
