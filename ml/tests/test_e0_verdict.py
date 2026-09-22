"""The E0 gate's verdict says what SPEC 0044 requires of it.

One test per acceptance criterion of
`docs/specs/0044-four-arm-e0-feasibility-gate.md` that only the verdict can
cover, named after the criterion. These are assertions about a committed
document, so they read no dataset, import no TensorFlow and run everywhere the
suite runs — which is the point SPEC 0043 makes: a criterion covered only where
the suite skips is not covered.

The numbers themselves live in `models/v1/`, which ADR 0019 keeps out of the
checkout. What is asserted here is that the committed record *states* them, and
states the things a reader would otherwise have to take on trust.
"""

import re
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VERDICT = REPOSITORY_ROOT / "docs" / "ml" / "e0-verdict.md"

#: The archive's vocabulary. Named here to assert their **absence**: a per-class
#: figure is a diagnostic this document is forbidden to quote as a result, and
#: the cheapest check that none crept in is that no class is named beside a
#: number anywhere in it.
ARCHIVE_CLASSES = ("Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa")

#: SPEC 0044's four adoption conditions, in the order the rule states them.
ADOPTION_CONDITIONS = (
    "Executed",
    "Won the secondary contrast",
    "Fast enough",
    "Amendments accepted",
)


@pytest.fixture(scope="module")
def verdict() -> str:
    assert VERDICT.is_file(), f"{VERDICT} is the gate's committed record and is missing"
    return VERDICT.read_text(encoding="utf-8")


def condition_row(verdict: str, condition: str) -> list[str] | None:
    """The cells of the table row recording [condition], or `None` if it has none.

    Read as a row rather than as a substring because the criterion is that each
    condition carries *its own* outcome: a document that names all four and
    resolves three of them satisfies every substring search over the whole file
    and is exactly what SPEC 0044 forbids.
    """
    for line in verdict.splitlines():
        if line.startswith("|") and f"**{condition}**" in line:
            return [cell.strip() for cell in line.strip().strip("|").split("|")]
    return None


def test_verdict_states_each_decision_rule_condition_by_name(verdict):
    """All four adoption conditions, each recorded met or not met, with evidence.

    Four and not "the rule": they fail for different reasons and must be
    auditable separately. An encoder no hardware can run fails condition 1, and
    recording that as a lost comparison would put a conclusion in the record the
    experiment never reached.
    """
    for condition in ADOPTION_CONDITIONS:
        cells = condition_row(verdict, condition)
        assert cells is not None, f"condition {condition!r} is not recorded by name"
        outcome = cells[2]
        assert re.match(r"\*\*(yes|no)\b", outcome), (
            f"condition {condition!r} is named but its row records "
            f"{outcome!r} rather than met or not met"
        )

    # An unmeasured condition and an unsought one are both recorded as not met,
    # and each says which it is: "no" alone would let a later reader take the
    # latency gate for a comparison the encoder lost.
    assert condition_row(verdict, "Fast enough")[2] == "**no — not run**"
    assert condition_row(verdict, "Amendments accepted")[2] == "**no — not sought**"

    # And the document says which path ships rather than leaving it to be
    # inferred from the table.
    assert "the descriptor path ships" in verdict


def test_verdict_is_committed_whichever_way_it_returns(verdict):
    """The numbers, the seeds, the dataset version, the digest and the stack."""
    assert "`v1`" in verdict
    assert "49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9" in verdict
    assert "42, 1042, 2042, 3042, 4042" in verdict

    for library in ("TensorFlow 2.21.0", "Keras 3.14.0", "scikit-learn 1.5.2", "numpy 1.26.4"):
        assert library in verdict, f"{library} is not recorded"

    # The headline figure of every arm, including the control it is read against.
    for arm in ("shuffled_control", "cnn", "descriptors", "encoder_probe"):
        assert f"`{arm}`" in verdict


def test_the_divergence_from_the_pinned_stack_is_stated_rather_than_discovered(verdict):
    """The run used Keras 3.14.0 and `requirements.txt` pins 3.15.1 (SPEC 0060).

    A reader reproducing these numbers under the pin gets a different stack and
    nothing in the record would have told them.
    """
    # Anchored on what pins the version rather than on the number: the number
    # appears in the reproduction block too, so a bare substring search would
    # survive the divergence section being quietly corrected to agree with the
    # run.
    assert re.search(r"`ml/requirements\.txt`[^.]*3\.15\.1", verdict), (
        "the verdict does not say that `ml/requirements.txt` pins 3.15.1"
    )
    assert re.search(r"reproduc\w+ .{0,40}3\.14\.0", verdict, re.IGNORECASE | re.DOTALL)


def test_descriptor_ablation_names_each_component_contribution(verdict):
    """Every component group, removed in turn, with its own number."""
    for group in ("first_order", "spectral", "lbp", "glcm"):
        assert f"`{group}`" in verdict, f"the ablation does not name {group!r}"

    # The one that carries the arm, and the size of what it carries.
    assert "0.1558" in verdict
    assert "0.5325" in verdict

    # And the limit of a leave-one-out design, which its shape invites a reader
    # to forget: individually removable is not jointly removable.
    assert "given the other three" in verdict


def test_no_per_class_figure_is_a_headline(verdict):
    """No class is named in this document, let alone quoted as a result.

    The per-class figures exist in `metrics.json` carrying `"headline": false`.
    The rule this asserts is the stronger half: the committed record quotes none
    of them, because a per-class figure here rests on three to four test groups
    per fold.
    """
    for soil_class in ARCHIVE_CLASSES:
        assert soil_class not in verdict, f"{soil_class!r} is named in the verdict"

    assert "headline" in verdict


def test_negative_verdict_blocks_lane_c(verdict):
    """The rule for a negative result is recorded although it did not fire.

    Written down in the same document that reports a positive result, so it
    cannot be re-read favourably later: at this N a failure to reject is not
    evidence for the null, and the consequence was fixed in advance.
    """
    # One conditional, not three phrases a reader has to join: the antecedent
    # and both halves of the consequence in the same sentence. A document that
    # carries the words scattered across sections passes every substring search
    # while stating no rule at all.
    rule = re.search(
        # No `.` between the two halves: that is what makes this one sentence
        # rather than two that happen to be adjacent.
        r"had no arm cleared the control[^.]*no Lane C item would start[^.]*\.",
        verdict,
        re.IGNORECASE,
    )
    assert rule, "the negative-verdict rule is not recorded as one conditional"
    assert "signal was not demonstrated" in rule.group(0)

    # Stated once, and in the registered terms. SPEC 0044 defines clearing the
    # control as Holm-corrected significance *and* a difference at or above the
    # contrast's own minimum detectable effect, and the stop condition is the
    # negation of exactly that. Both clauses are asserted rather than only the
    # phrase that was wrong before, because a predicate swapped for a looser one
    # — a macro-F1 threshold, a spread — names neither and would otherwise pass.
    flat = " ".join(verdict.split())
    stop = re.search(
        r"if no arm clears a label-shuffled control.{0,400}?Lane C stops\.", flat
    )
    assert stop, "the stop condition is not stated where the document opens"
    for clause in ("exact McNemar test", "Holm correction", "minimum detectable effect"):
        assert clause in stop.group(0), (
            f"the stop condition does not name {clause!r}, so it is not the "
            f"predicate SPEC 0044 registered"
        )

    # And the one it used to state instead, which no section may reintroduce.
    assert "run-to-run variance" not in verdict, (
        "the stop condition is stated as run-to-run variance, which SPEC 0044 "
        "does not register"
    )

    # And the document says which branch it actually took.
    assert "Signal was demonstrated" in verdict


def test_an_arm_that_did_not_run_is_not_recorded_as_having_lost(verdict):
    """All four arms ran, and the verdict says so rather than leaving it implicit."""
    assert "`not_executed` empty" in verdict


def test_the_verdict_does_not_adopt_a_method(verdict):
    """SPEC 0044 reserves adoption for an ADR written against these numbers.

    The distinction is not pedantry: "the descriptor path ships" is the
    pre-registered rule resolving, and adopting it is a decision with record
    amendments attached that this document is not allowed to take.
    """
    assert "does not adopt a method" in verdict
