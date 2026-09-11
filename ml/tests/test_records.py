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

#: Wording that says a decision has not been taken. A living pointer carrying one
#: of these in a block that also names ADR 0021 is a record still waiting for a
#: decision that has been made.
#:
#: The list was eight entries and caught none of the phrasings these documents
#: actually use — "awaiting" among them, which is the word SPEC 0062's own
#: criterion names and which `ml-implementation-map.md` used. Each entry below
#: was added because a real or plausible sentence escaped the previous list, not
#: because it sounded like it belonged.
PENDING_MARKERS = (
    "undecided",
    "pending",
    "awaits",
    "awaiting",
    "waits on",
    "waits,",
    "still waits",
    "waiting on",
    # "blocked on" is deliberately absent: it is the header of a legitimate
    # column in the map's queue table, so it appears in the same block as the
    # ADR 0021 row while saying nothing about whether the decision is taken.
    # The phrasings that would actually claim it is pending are below.
    "blocked until",
    "cannot run until",
    "is not yet",
    "has not been taken",
    "has not written",
    "still to be",
    "remains open",
    "the developer takes it",
    "yet to be",
    "tbd",
)

#: The D6 decision under every name these documents give it. The first guard
#: written here looked only for the literal "adr 0021" and missed the handoff's
#: own "The gate still waits … E0 has to run the arms D6 settles on", which says
#: the same thing without the number.
DECISION_NAMES = ("adr 0021", "d6 decision", "d6 settles", "the d6 ")


def adr_0021() -> Path:
    """The decision record, or a failure naming what is missing."""
    matches = sorted(ADR_DIR.glob("0021-*.md"))
    if not matches:
        pytest.fail(f"no ADR numbered 0021 under {ADR_DIR}")
    assert len(matches) == 1, f"more than one ADR 0021: {matches}"
    return matches[0]


def adr_0021_text() -> str:
    return adr_0021().read_text(encoding="utf-8")


def section(text: str, heading: str) -> str:
    """The body of one ``##`` section, or "" when the heading is absent.

    Every assertion below reads a section rather than the whole document. The
    first version of this module searched the full text, and an adversarial
    review showed what that buys: rewriting the Decision section to its exact
    opposite — *"D6 is reversed ... may never enter any training side"* — still
    passed, because "stands" was satisfied by the quoted SPEC 0057 verdict
    elsewhere in the file. A substring test over a long document mostly asserts
    that the document is long.
    """
    marker = f"## {heading}"
    if marker not in text:
        return ""
    body = text.split(marker, 1)[1]
    return body.split(f"{LINE_BREAK}## ", 1)[0]


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
    decision = section(adr_0021_text(), "Decision").lower()

    assert decision, "ADR 0021 has no ## Decision section"
    assert "d6" in decision
    assert "stands" in decision or "unchanged" in decision, (
        "the Decision section does not state that D6 is unchanged"
    )
    assert "may train" in decision, (
        "the Decision section does not say that B may still train"
    )
    assert re.search(r"may never be (validated|tested)", decision), (
        "the Decision section does not state the half of D6 that binds"
    )
    # The negation, refused by name. Without these two the reversal of the
    # decision — "D6 is reversed ... may never enter any training side" — passes
    # every assertion above, which is what the adversarial review demonstrated.
    assert "reversed" not in decision, "the Decision section says D6 is reversed"
    assert not re.search(r"never (enter|be used in) any training", decision), (
        "the Decision section keeps B out of training, which is the opposite of "
        "what this record decides"
    )


# --- adr_0021_names_both_rejected_options ----------------------------------


def test_adr_0021_names_both_rejected_options():
    """Both pre-registered options appear, so unchanged cannot read as unconsidered.

    SPEC 0055 fixed two branches before the numbers existed. A decision record
    that mentions neither leaves a reader unable to tell a choice from an
    oversight.
    """
    rejected = section(adr_0021_text(), "Options rejected").lower()

    assert rejected, "ADR 0021 has no ## Options rejected section"
    assert "leaves training" in rejected or "leave training" in rejected, (
        "the Options rejected section does not name the option where B leaves "
        "training entirely"
    )
    assert "restrict" in rejected, (
        "the Options rejected section does not name the option where B is "
        "restricted to eligible arms"
    )
    # A named option with no reason is a list, not a rejection. Read from the
    # section for the same reason as above: deleting the whole section left the
    # earlier version of this test passing, because the narrative paragraphs
    # mention both options in passing.
    assert rejected.count("rejected") >= 2, (
        "the Options rejected section does not give a reason per option"
    )


# --- adr_0021_records_the_per_class_cost -----------------------------------


def test_adr_0021_records_the_per_class_cost():
    """The number the decision turns on is in the record, not only in the spec.

    Argilosa falls from 33 sample groups to 16 if B leaves training. An ADR that
    rejected that option without carrying its cost would be asserting a judgement
    a later reader could not check.
    """
    text = adr_0021_text()

    # "Argilosa" alone is satisfied by "Muito Argilosa", so the class that pays
    # could not be told from the class that pays nothing. A negative lookbehind
    # separates them.
    assert re.search(r"(?<!Muito )\bArgilosa\b", text), (
        "ADR 0021 does not name Argilosa, the class that pays"
    )

    # Asserted as a pair on one table row rather than as two bare integers
    # anywhere in the file: 31 and 16 in isolation are satisfied by a year, a
    # line number or an unrelated percentage.
    row = re.search(r"\|\s*\**(?<!Muito )Argilosa\**\s*\|(?P<cells>[^\n]*)", text)
    assert row, "ADR 0021 has no Argilosa row in its cost table"

    cells = row.group("cells")
    assert re.search(r"\b31\b", cells), (
        f"the Argilosa row does not carry the count with B: {cells!r}"
    )
    assert re.search(r"\b16\b", cells), (
        f"the Argilosa row does not carry the count without B: {cells!r}"
    )


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
            if not any(name in lowered for name in DECISION_NAMES):
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
            names_the_adr = any(name in lowered for name in DECISION_NAMES)
            names_the_gate = "#216" in block or "spec 0044" in lowered or (
                "the gate" in lowered or "e0" in lowered
            )
            if names_the_adr and names_the_gate and "waits" in lowered:
                offenders.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}:{number}: "
                    f"{block.splitlines()[0].strip()}"
                )

    assert not offenders, "\n".join(offenders)
