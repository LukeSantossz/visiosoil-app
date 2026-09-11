"""The D6 decision reached the records that were waiting for it (SPEC 0062).

One test per acceptance criterion, named after the criterion. Nothing here reads
the dataset or imports TensorFlow: these are assertions about documents, so they
run everywhere the suite runs.

**Two directories are deliberately not scanned.** `docs/specs/` and `docs/ml/`
are durable archives — an approved spec keeps the text it was approved with, and
a run verdict records what was measured — so both legitimately still say ADR 0021
is the decision they point forward to. What this module checks is the *living*
pointers: the architecture documents a reader consults to find out what to do
next, and the README index.
"""

import re
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ADR_DIR = REPOSITORY_ROOT / "docs" / "adr"
ARCHITECTURE_DIR = REPOSITORY_ROOT / "docs" / "architecture"
README = REPOSITORY_ROOT / "README.md"

#: Joined with rather than written inline, so the separator a block is rebuilt
#: with is one named thing and not an escape repeated in two places.
LINE_BREAK = "\n"

#: Wording that says a decision has not been taken. A living pointer carrying
#: one of these on a line that also names ADR 0021 is a record still waiting for
#: a decision that has been made.
PENDING_MARKERS = (
    "undecided",
    "pending",
    "waits on",
    "waiting on",
    "is not yet",
    "the developer takes it",
    "yet to be",
)


def adr_0021() -> Path:
    """The decision record, or a failure naming what is missing."""
    matches = sorted(ADR_DIR.glob("0021-*.md"))
    if not matches:
        pytest.fail(f"no ADR numbered 0021 under {ADR_DIR}")
    assert len(matches) == 1, f"more than one ADR 0021: {matches}"
    return matches[0]


def adr_0021_text() -> str:
    return adr_0021().read_text(encoding="utf-8")


def living_pointers() -> list[Path]:
    """The documents a reader consults for what to do next."""
    return sorted(ARCHITECTURE_DIR.glob("*.md")) + [README]


def blocks(path: Path):
    """Yield ``(first line number, text)`` for each blank-line-separated block.

    Scanned by block rather than by line because that is how these documents are
    written: the sentence naming ADR 0021 and the sentence saying it is untaken
    are usually neighbours, not the same line. A line-scoped version of this
    check passed over the map's own "The Developer takes it." for exactly that
    reason, and a guard that cannot fail is not a guard.
    """
    start = 1
    current: list[str] = []
    for number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        # A bare ``>`` is the paragraph break *inside* a blockquote. Without it
        # these documents' long quoted revision notes read as one 98-line block,
        # and a sentence about some other issue's Dart half lands in the same
        # block as ADR 0021 — a false positive that would teach the next reader
        # to widen the exclusion list rather than fix the record.
        if line.strip() and line.strip() != ">":
            if not current:
                start = number
            current.append(line)
            continue
        if current:
            yield start, LINE_BREAK.join(current)
            current = []
    if current:
        yield start, LINE_BREAK.join(current)


# --- adr_0021_exists_and_states_the_decision -------------------------------


def test_adr_0021_exists_and_states_the_decision():
    """The record exists and says D6 is unchanged, in words a reader can find.

    Asserted on the claim rather than on a title, because a record named after
    the decision and silent about it would pass a title check and tell a reader
    nothing.
    """
    text = adr_0021_text().lower()

    assert "d6" in text
    assert "stands" in text or "unchanged" in text, (
        "ADR 0021 does not state that D6 is unchanged"
    )
    assert "may train" in text or "training side" in text, (
        "ADR 0021 does not say what B may still do"
    )
    assert "never" in text, "ADR 0021 does not state the half of D6 that binds"


# --- adr_0021_names_both_rejected_options ----------------------------------


def test_adr_0021_names_both_rejected_options():
    """Both pre-registered options appear, so unchanged cannot read as unconsidered.

    SPEC 0055 fixed two branches before the numbers existed. A decision record
    that mentions neither leaves a reader unable to tell a choice from an
    oversight.
    """
    text = adr_0021_text().lower()

    assert "leaves training" in text or "leave training" in text, (
        "ADR 0021 does not name the option where B leaves training entirely"
    )
    assert "restrict" in text, (
        "ADR 0021 does not name the option where B is restricted to eligible arms"
    )


# --- adr_0021_records_the_per_class_cost -----------------------------------


def test_adr_0021_records_the_per_class_cost():
    """The number the decision turns on is in the record, not only in the spec.

    Argilosa falls from 33 sample groups to 16 if B leaves training. An ADR that
    rejected that option without carrying its cost would be asserting a judgement
    a later reader could not check.
    """
    text = adr_0021_text()

    assert "Argilosa" in text, "ADR 0021 does not name the class that pays"
    assert re.search(r"\b33\b", text), "ADR 0021 does not carry the count with B"
    assert re.search(r"\b16\b", text), "ADR 0021 does not carry the count without B"


# --- readme_indexes_adr_0021 -----------------------------------------------


def test_readme_indexes_adr_0021():
    """The README Engineering Decisions section links the record.

    `test/standards/readme_adr_index_test.dart` already enforces this for every
    ADR. It is asserted here too because that suite does not run in the
    `ml-tests` job, and a criterion whose only guard is in another language's
    suite is one this module cannot report on.
    """
    link = adr_0021().relative_to(REPOSITORY_ROOT).as_posix()

    assert link in README.read_text(encoding="utf-8"), (
        f"README does not link {link}"
    )


# --- no_record_still_waits_on_adr_0021 -------------------------------------


def test_no_record_still_waits_on_adr_0021():
    """No living pointer still describes the decision as untaken."""
    offenders = []

    for path in living_pointers():
        for number, block in blocks(path):
            lowered = block.lower()
            if "adr 0021" not in lowered:
                continue
            for marker in PENDING_MARKERS:
                if marker in lowered:
                    offenders.append(
                        f"{path.relative_to(REPOSITORY_ROOT)}:{number} "
                        f"still says {marker!r}"
                    )

    assert not offenders, "\n".join(offenders)


# --- the_records_agree_on_what_blocks_the_gate -----------------------------


def test_the_records_agree_on_what_blocks_the_gate():
    """Neither the handoff nor the map names ADR 0021 as the gate's blocker.

    Checked as a pair rather than one document at a time: the failure this
    guards is the two disagreeing, which is what sent an earlier session down a
    path the other document had already closed.
    """
    offenders = []

    for name in ("ml-handoff.md", "ml-implementation-map.md"):
        path = ARCHITECTURE_DIR / name
        assert path.exists(), f"{path} is missing"
        for number, block in blocks(path):
            lowered = block.lower()
            names_the_adr = "adr 0021" in lowered
            names_the_gate = "#216" in block or "spec 0044" in lowered
            if names_the_adr and names_the_gate and "waits" in lowered:
                offenders.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}:{number}: "
                    f"{block.splitlines()[0].strip()}"
                )

    assert not offenders, "\n".join(offenders)
