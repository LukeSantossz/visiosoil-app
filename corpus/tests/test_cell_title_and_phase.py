"""A tip's optional title and crop phase pass through the cell contract
(SPEC 0209)."""

import pytest

from src.cell import CellValidationError, build_cell_payload, validate_cell


def _cell(**tip):
    return {
        "status": "grounded",
        "disclaimer": "Consultivo.",
        "tips": [{"text": "Evite tráfego com solo úmido.", "citations": [0], **tip}],
        "sources": [{"title": "Guia"}],
        "limitations": [],
    }


def test_the_payload_keeps_title_and_phase():
    payload = build_cell_payload(
        status="grounded",
        disclaimer="Consultivo.",
        tips=[
            {
                "text": "Evite tráfego com solo úmido.",
                "citations": [0],
                "title": "Evite tráfego com solo úmido",
                "phase": "before_planting",
            }
        ],
        sources=[{"title": "Guia"}],
        limitations=[],
    )

    tip = payload["tips"][0]
    assert tip["title"] == "Evite tráfego com solo úmido"
    assert tip["phase"] == "before_planting"


def test_the_payload_omits_absent_title_and_phase():
    payload = build_cell_payload(
        status="grounded",
        disclaimer="Consultivo.",
        tips=[{"text": "Mantenha a palhada.", "citations": [0]}],
        sources=[{"title": "Guia"}],
        limitations=[],
    )

    assert "title" not in payload["tips"][0]
    assert "phase" not in payload["tips"][0]


@pytest.mark.parametrize("phase", ["before_planting", "sowing", "crop_cycle"])
def test_a_known_phase_passes(phase):
    validate_cell(_cell(title="Evite tráfego", phase=phase), source_count=1)


def test_an_empty_title_fails_the_contract():
    with pytest.raises(CellValidationError, match="title"):
        validate_cell(_cell(title="  "), source_count=1)


def test_an_unknown_phase_fails_the_contract():
    with pytest.raises(CellValidationError, match="phase"):
        validate_cell(_cell(phase="harvest"), source_count=1)
