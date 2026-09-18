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


@pytest.fixture(scope="module")
def verdict() -> str:
    assert VERDICT.is_file(), f"{VERDICT} is the gate's committed record and is missing"
    return VERDICT.read_text(encoding="utf-8")


def test_verdict_states_each_decision_rule_condition_by_name(verdict):
    """All four adoption conditions, each recorded met or not met, with evidence.

    Four and not "the rule": they fail for different reasons and must be
    auditable separately. An encoder no hardware can run fails condition 1, and
    recording that as a lost comparison would put a conclusion in the record the
    experiment never reached.
    """
    for condition in ("Executed", "Won the secondary contrast", "Fast enough", "Amendments accepted"):
        assert condition in verdict, f"condition {condition!r} is not recorded by name"

    # Each condition's row carries a verdict, and the document says which path
    # ships rather than leaving it to be inferred from the table.
    assert "the descriptor path ships" in verdict
    assert "not run" in verdict and "not sought" in verdict


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
    assert "3.15.1" in verdict
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
    assert "signal was not demonstrated" in verdict
    assert "no Lane C item would start" in verdict

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
