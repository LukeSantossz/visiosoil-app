"""The descriptor path's adoption reached the records (SPEC 0073).

One test per acceptance criterion, named after the criterion. Nothing here reads
the dataset or imports TensorFlow: these are assertions about documents, so they
run everywhere the suite runs.

The block and section helpers are SPEC 0062's, imported rather than copied, so
both guards read the documents the same way. `docs/specs/` and `docs/ml/` stay
out of every scan for the reason given there: an approved spec and a run verdict
keep the text they were written with.
"""

import re
from pathlib import Path

import pytest

from tests.test_records import (
    ADR_DIR,
    ARCHITECTURE_DIR,
    PENDING_MARKERS,
    README,
    REPOSITORY_ROOT,
    blocks,
    living_pointers,
    section,
)

VERDICT = "ml/e0-verdict.md"
GATE_SPEC = "0044-four-arm-e0-feasibility-gate.md"
AMENDMENT_HEADING = "### Amended 2026-09-22"

#: SPEC 0044's four adoption conditions, each with the outcome
#: `docs/ml/e0-verdict.md` records for it. A record that names a condition
#: without its outcome reads as though the condition were still to be checked.
CONDITION_OUTCOMES = {
    "executed": "yes",
    "won the secondary contrast": "no",
    "fast enough": "not run",
    "amendments accepted": "not sought",
}

#: How the living records say the gate is still to run. Each came from a
#: sentence the map or the handoff carried when SPEC 0073 was written.
GATE_NEXT_PHRASES = (
    "the gate is next",
    "gate is the next thing to run",
    "run the gate",
    "are the next items",
    "nothing in front of it",
)

#: The adoption under the names the records give it.
ADOPTION_NAMES = ("adoption adr", "adoption decision", "adopting a method")


def the_adr(number: str) -> Path:
    """The single ADR numbered [number], or a failure naming what is missing."""
    matches = sorted(ADR_DIR.glob(f"{number}-*.md"))
    if not matches:
        pytest.fail(f"no ADR numbered {number} under {ADR_DIR}")
    assert len(matches) == 1, f"more than one ADR {number}: {matches}"
    return matches[0]


def adr_0024_text() -> str:
    return the_adr("0024").read_text(encoding="utf-8")


def flattened(text: str) -> str:
    """[text] lower-cased with its line breaks folded, so a phrase the
    documents wrap across two lines is still one phrase."""
    return " ".join(text.lower().split())


# --- adr_0024_adopts_the_descriptor_path -----------------------------------


def test_adr_0024_adopts_the_descriptor_path():
    text = adr_0024_text()
    decision = flattened(section(text, "Decision"))

    assert "descriptor path" in decision and "ships" in decision, (
        "ADR 0024's Decision section does not state that the descriptor path ships"
    )
    assert GATE_SPEC in text, "ADR 0024 does not link SPEC 0044, whose rule it applies"
    assert VERDICT in text, "ADR 0024 does not link the verdict it adopts from"


# --- adr_0024_records_each_adoption_condition ------------------------------


def test_adr_0024_records_each_adoption_condition():
    """Each condition sits on one line with its outcome, as the verdict's table
    puts them, so neither can be edited apart from the other unnoticed."""
    lines = [flattened(line) for line in adr_0024_text().splitlines()]
    missing = [
        f"{condition!r} with {outcome!r}"
        for condition, outcome in CONDITION_OUTCOMES.items()
        if not any(
            condition in line and re.search(rf"\b{re.escape(outcome)}\b", line)
            for line in lines
        )
    ]

    assert not missing, "ADR 0024 does not record: " + ", ".join(missing)


# --- adr_0024_decides_the_runtime ------------------------------------------


def test_adr_0024_decides_the_runtime():
    decision = flattened(section(adr_0024_text(), "Decision"))

    for required in ("dart", "spec.json", "standardiser", "coefficients"):
        assert required in decision, (
            f"ADR 0024's Decision section does not say {required!r}"
        )


# --- adr_0024_names_the_rejected_options -----------------------------------


def test_adr_0024_names_the_rejected_options():
    options = flattened(section(adr_0024_text(), "Considered Options"))

    for option in ("tflite", "encoder", "cnn", "onnx"):
        assert option in options, (
            f"ADR 0024's Considered Options does not name {option!r}"
        )


# --- adr_0008_carries_its_amendment ----------------------------------------


def test_adr_0008_carries_its_amendment():
    text = the_adr("0008").read_text(encoding="utf-8")

    assert AMENDMENT_HEADING in text, f"ADR 0008 has no {AMENDMENT_HEADING!r}"
    amendment = re.split(r"\n#{2,3} ", text.split(AMENDMENT_HEADING, 1)[1], 1)[0]
    assert the_adr("0024").name in amendment, (
        "ADR 0008's amendment does not link ADR 0024"
    )


# --- spec_0035_points_to_adr_0024 ------------------------------------------


def test_spec_0035_points_to_adr_0024():
    """The pointer sits in the revision notes above the Problem, where a reader
    meets it before the schema it corrects."""
    spec = next((REPOSITORY_ROOT / "docs" / "specs").glob("0035-*.md"))
    preamble = spec.read_text(encoding="utf-8").split("## Problem", 1)[0]

    assert the_adr("0024").name in preamble, (
        "SPEC 0035's revision notes do not name ADR 0024"
    )


# --- readme_indexes_adr_0024 -----------------------------------------------


def test_readme_indexes_adr_0024():
    """Also enforced by `test/standards/readme_adr_index_test.dart`, which does
    not run in the `ml-tests` job — hence here too, as SPEC 0062 did."""
    link = the_adr("0024").relative_to(REPOSITORY_ROOT).as_posix()

    assert link in README.read_text(encoding="utf-8"), f"README does not link {link}"


# --- no_living_record_calls_the_gate_next ----------------------------------


def test_no_living_record_calls_the_gate_next():
    """A block may still say the gate was next — the map keeps its history — but
    only beside a link to the verdict that says it ran."""
    offenders = []

    for name in ("ml-handoff.md", "ml-implementation-map.md"):
        path = ARCHITECTURE_DIR / name
        assert VERDICT in path.read_text(encoding="utf-8"), (
            f"{name} does not link {VERDICT}"
        )
        for number, block in blocks(path):
            text = flattened(block)
            if VERDICT in block:
                continue
            for phrase in GATE_NEXT_PHRASES:
                if phrase in text:
                    offenders.append(f"{name}:{number} still says {phrase!r}")

    assert not offenders, "\n".join(offenders)


# --- no_living_record_waits_on_the_adoption --------------------------------


def test_no_living_record_waits_on_the_adoption():
    offenders = []

    for path in living_pointers():
        for number, block in blocks(path):
            text = flattened(block)
            if not any(name in text for name in ADOPTION_NAMES):
                continue
            for marker in PENDING_MARKERS + ("not taken",):
                if marker in text:
                    offenders.append(
                        f"{path.relative_to(REPOSITORY_ROOT)}:{number} "
                        f"still says {marker!r}"
                    )

    assert not offenders, "\n".join(offenders)
