"""Tests for the collection protocol document (SPEC 0033).

The protocol is executed by a person, not by code, so what it states is the
deliverable. Three of its rules are asserted here because each one was decided
against an alternative and a silent edit would undo the decision: where the coin
goes, how the fill rule is phrased, and that the `paper` condition uses a
template.

Assertions are on the load-bearing phrases rather than on whole paragraphs, so
the document can be rewritten for clarity without failing this suite.
"""

from pathlib import Path

import pytest

PROTOCOL_PATH = (
    Path(__file__).resolve().parents[2] / "docs" / "ml" / "collection-protocol.md"
)


@pytest.fixture(scope="module")
def protocol() -> str:
    return PROTOCOL_PATH.read_text(encoding="utf-8")


def test_the_protocol_document_exists():
    """A protocol nobody can read is not a protocol."""
    assert PROTOCOL_PATH.is_file(), f"expected {PROTOCOL_PATH}"


def test_protocol_document_states_the_coin_placement(protocol):
    """The coin sits outside the analysed square, and the reason is stated.

    A coin inside the region of interest is a smooth metal disc: it lowers
    Laplacian variance and raises the specular fraction, so the criteria would
    penalise compliance with the protocol.
    """
    assert "outside the centred square" in protocol
    assert "Laplacian" in protocol
    assert "specular" in protocol


def test_protocol_document_states_the_fill_rule_operationally(protocol):
    """The rule is phrased over the guide circle, with no percentage."""
    assert "touches the guide circle" in protocol
    assert "70 %" not in protocol
    assert "70%" not in protocol


def test_protocol_document_admits_the_container_rim(protocol):
    """The dish rim is the target boundary, so it cannot be forbidden."""
    assert "rim" in protocol


def test_protocol_document_states_the_paper_template(protocol):
    """The paper condition uses a 90 mm template, and the reason is stated."""
    assert "90 mm template" in protocol
    assert "neither constant nor recorded" in protocol


def test_protocol_document_states_that_fresh_soil_is_not_covered(protocol):
    """No accuracy figure from this dataset describes fresh material."""
    assert "air-dried" in protocol
    assert "in_situ" in protocol


def test_protocol_document_names_the_two_tools_a_collector_runs(protocol):
    """A protocol that cannot be checked is a protocol nobody follows."""
    assert "scripts/admit_images.py" in protocol
    assert "scripts/validate_dataset.py" in protocol
