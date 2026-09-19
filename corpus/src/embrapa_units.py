"""Which Embrapa unit answers for a biome.

ADR 0022 moved biome from the substance key to the institutional layer on the
ground that "Embrapa's decentralised units are themselves biome-shaped". That is
true of four of the six, and this table is where the other two are handled
honestly rather than forced.

It is a **lookup, not generated guidance**: read once as part of the corpus
review, and not one of the 44 artifacts the budget and the review burden count.
"""

from __future__ import annotations

from typing import Any

UNIT_BY_BIOME: dict[str, dict[str, Any]] = {
    "amazonia": {
        "name": "Embrapa Amazônia Oriental",
        "city": "Belém",
        "unit": "BR-PA",
        "caveat": (
            "A Embrapa mantém duas unidades na Amazônia: a Oriental, em Belém, "
            "e a Ocidental, em Manaus. A indicação padrão é a Oriental."
        ),
    },
    "cerrado": {
        "name": "Embrapa Cerrados",
        "city": "Planaltina",
        "unit": "BR-DF",
        "caveat": "",
    },
    "mata_atlantica": {
        "name": "Embrapa Florestas",
        "city": "Colombo",
        "unit": "BR-PR",
        "caveat": (
            "Nenhuma unidade da Embrapa leva o nome do bioma Mata Atlântica. "
            "A indicação é a unidade cuja área de atuação mais se aproxima; "
            "a assistência técnica estadual costuma ser a referência melhor."
        ),
    },
    "caatinga": {
        "name": "Embrapa Semiárido",
        "city": "Petrolina",
        "unit": "BR-PE",
        "caveat": "",
    },
    "pampa": {
        "name": "Embrapa Clima Temperado",
        "city": "Pelotas",
        "unit": "BR-RS",
        "caveat": (
            "A Embrapa Pecuária Sul, em Bagé, atende o Pampa na pecuária; "
            "para solo e manejo a indicação é a Clima Temperado."
        ),
    },
    "pantanal": {
        "name": "Embrapa Pantanal",
        "city": "Corumbá",
        "unit": "BR-MS",
        "caveat": "",
    },
}


def unit_for_biome(biome: str | None) -> dict[str, Any] | None:
    """The entry for [biome], or null for one the table does not cover."""
    if not biome:
        return None
    return UNIT_BY_BIOME.get(biome)
