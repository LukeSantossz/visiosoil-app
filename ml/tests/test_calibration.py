"""Confidence, coverage and calibration read from stored distributions (SPEC 0095).

Every expected value below is worked by hand from the six photographs in
`DISTRIBUTIONS`, not by calling numpy on them, so a wrong formula cannot agree
with itself. The arithmetic is written beside each figure.
"""

import pytest

from src.calibration import (
    CALIBRATION_BINS,
    calibration_error,
    confidence_record,
    coverage_sweep,
    percentiles,
    severity_record,
)
from tests.support import configured_classes

#: Arenosa, Media, Muito Argilosa, Argilosa: the indices below follow this order,
#: which `test_config_declares_four_classes_without_siltosa` pins.
CLASSES = configured_classes()

# label, distribution, and what it gives: top-1, margin, predicted class, right.
DISTRIBUTIONS = [
    (0, [0.70, 0.20, 0.05, 0.05]),  # 0.70, 0.50, Arenosa, right
    (1, [0.40, 0.35, 0.15, 0.10]),  # 0.40, 0.05, Arenosa, wrong
    (1, [0.10, 0.60, 0.20, 0.10]),  # 0.60, 0.40, Media, right
    (2, [0.05, 0.05, 0.85, 0.05]),  # 0.85, 0.80, Muito Argilosa, right
    (2, [0.30, 0.10, 0.25, 0.35]),  # 0.35, 0.05, Argilosa, wrong
    (3, [0.72, 0.08, 0.10, 0.10]),  # 0.72, 0.62, Arenosa, wrong
]
LABELS = [label for label, _ in DISTRIBUTIONS]
PROBABILITIES = [distribution for _, distribution in DISTRIBUTIONS]
GROUPS = ["g1", "g2", "g2", "g3", "g4", "g5"]


def _point(points, threshold):
    return next(p for p in points if p["threshold"] == pytest.approx(threshold))


def test_percentiles_match_a_hand_checked_fixture():
    record = confidence_record(LABELS, PROBABILITIES, GROUPS, CLASSES)

    # Top-1 sorted: 0.35 0.40 0.60 0.70 0.72 0.85. Linear interpolation at
    # position p/100 * 5: p10 at 0.5, p50 at 2.5, p90 at 4.5.
    assert record["top1"]["p10"] == pytest.approx(0.375)  # 0.35 + 0.5 * 0.05
    assert record["top1"]["p50"] == pytest.approx(0.65)  # 0.60 + 0.5 * 0.10
    assert record["top1"]["p90"] == pytest.approx(0.785)  # 0.72 + 0.5 * 0.13
    # Margins sorted: 0.05 0.05 0.40 0.50 0.62 0.80.
    assert record["margin"]["p10"] == pytest.approx(0.05)
    assert record["margin"]["p50"] == pytest.approx(0.45)  # 0.40 + 0.5 * 0.10
    assert record["margin"]["p90"] == pytest.approx(0.71)  # 0.62 + 0.5 * 0.18

    assert record["level"] == "photograph"
    assert record["photographs"] == 6
    assert record["groups"] == 5
    assert percentiles([1.0, 3.0]) == pytest.approx({"p10": 1.2, "p50": 2.0, "p90": 2.8})


def test_the_calibration_error_matches_a_hand_computed_value():
    result = calibration_error(LABELS, PROBABILITIES)

    assert result["bins"] == CALIBRATION_BINS == 10
    # Occupied bins: [0.3, 0.4) holds 0.35 (wrong); [0.4, 0.5) holds 0.40
    # (wrong); [0.6, 0.7) holds 0.60 (right); [0.7, 0.8) holds 0.70 (right)
    # and 0.72 (wrong); [0.8, 0.9) holds 0.85 (right).
    # (0.35 + 0.40 + 0.40 + 2 * |0.5 - 0.71| + 0.15) / 6 = 1.72 / 6
    assert result["expected_calibration_error"] == pytest.approx(1.72 / 6)

    curve = result["reliability"]
    assert [b["count"] for b in curve] == [0, 0, 0, 1, 1, 0, 1, 2, 1, 0]
    assert curve[7]["low"] == pytest.approx(0.7)
    assert curve[7]["high"] == pytest.approx(0.8)
    assert curve[7]["mean_confidence"] == pytest.approx(0.71)
    assert curve[7]["accuracy"] == pytest.approx(0.5)
    assert curve[3]["accuracy"] == 0.0
    assert curve[6]["accuracy"] == 1.0


def test_an_empty_bin_reports_no_mean_and_no_accuracy():
    curve = calibration_error(LABELS, PROBABILITIES)["reliability"]

    for empty in (0, 1, 2, 5, 9):
        assert curve[empty]["count"] == 0
        assert curve[empty]["mean_confidence"] is None
        assert curve[empty]["accuracy"] is None


def test_the_sweep_reports_coverage_and_accuracy_at_coverage():
    sweep = coverage_sweep(LABELS, PROBABILITIES, CLASSES)

    top1 = sweep["top1"]["overall"]
    assert [p["threshold"] for p in top1] == pytest.approx(
        [0.25 + 0.05 * i for i in range(15)]
    )
    assert _point(top1, 0.25) == {
        "threshold": pytest.approx(0.25),
        "covered": 6,
        "coverage": 1.0,
        "accuracy": 0.5,
    }
    # A photograph at exactly the threshold is covered: 0.40 counts at 0.40.
    assert _point(top1, 0.40)["covered"] == 5
    assert _point(top1, 0.40)["accuracy"] == pytest.approx(3 / 5)
    assert _point(top1, 0.50)["coverage"] == pytest.approx(4 / 6)
    assert _point(top1, 0.50)["accuracy"] == pytest.approx(3 / 4)
    assert _point(top1, 0.70)["accuracy"] == pytest.approx(2 / 3)

    margin = sweep["margin"]["overall"]
    assert [p["threshold"] for p in margin] == pytest.approx(
        [0.05 * i for i in range(19)]
    )
    # 0.35 - 0.30 is 0.04999... in binary, and still reaches 0.05.
    assert _point(margin, 0.05)["covered"] == 6
    assert _point(margin, 0.10)["covered"] == 4
    assert _point(margin, 0.10)["accuracy"] == pytest.approx(3 / 4)

    # Per predicted class: Arenosa was predicted for 0.70 (right), 0.40 (wrong)
    # and 0.72 (wrong).
    arenosa = sweep["top1"]["per_predicted_class"]["Arenosa"]
    assert arenosa["headline"] is False
    assert arenosa["photographs"] == 3
    assert _point(arenosa["points"], 0.25)["accuracy"] == pytest.approx(1 / 3)
    assert _point(arenosa["points"], 0.50)["accuracy"] == pytest.approx(1 / 2)
    assert _point(arenosa["points"], 0.50)["coverage"] == pytest.approx(2 / 3)
    assert set(sweep["top1"]["per_predicted_class"]) == set(CLASSES)
    assert set(sweep["margin"]["per_predicted_class"]) == set(CLASSES)


def test_a_threshold_covering_nothing_reports_no_accuracy():
    sweep = coverage_sweep(LABELS, PROBABILITIES, CLASSES)

    assert _point(sweep["top1"]["overall"], 0.90) == {
        "threshold": pytest.approx(0.90),
        "covered": 0,
        "coverage": 0.0,
        "accuracy": None,
    }
    assert _point(sweep["margin"]["overall"], 0.85)["accuracy"] is None
    arenosa = sweep["top1"]["per_predicted_class"]["Arenosa"]["points"]
    assert _point(arenosa, 0.75)["accuracy"] is None

    # A class never predicted covers nothing at any threshold, and has no
    # coverage to state either.
    nothing = coverage_sweep([0], [[0.9, 0.05, 0.03, 0.02]], CLASSES)
    argilosa = nothing["top1"]["per_predicted_class"]["Argilosa"]
    assert argilosa["photographs"] == 0
    assert all(
        p["coverage"] is None and p["accuracy"] is None for p in argilosa["points"]
    )


# ADR 0016's ordering, restated here rather than imported, so the table under
# test cannot agree with itself.
EXPECTED_TIER = {
    ("Arenosa", "Muito Argilosa"): "most_serious",
    ("Arenosa", "Argilosa"): "serious",
    ("Media", "Muito Argilosa"): "serious",
    ("Arenosa", "Media"): "moderate",
    ("Media", "Argilosa"): "moderate",
    ("Argilosa", "Muito Argilosa"): "mild",
}


def test_confusions_are_counted_by_severity():
    for (one, other), tier in EXPECTED_TIER.items():
        for truth, predicted in ((one, other), (other, one)):
            pair = [(CLASSES.index(truth), CLASSES.index(predicted))]
            record = severity_record(pair, pair, CLASSES)
            assert record["photograph"][tier] == 1, (truth, predicted)
            assert record["photograph"]["correct"] == 0

    pairs = [
        (label, max(range(4), key=distribution.__getitem__))
        for label, distribution in DISTRIBUTIONS
    ]
    record = severity_record(pairs, pairs[:2], CLASSES)
    # Wrong: Media read as Arenosa (moderate), Muito Argilosa read as Argilosa
    # (mild), Argilosa read as Arenosa (serious).
    assert record["photograph"] == {
        "total": 6,
        "correct": 3,
        "most_serious": 0,
        "serious": 1,
        "moderate": 1,
        "mild": 1,
    }
    assert record["group"]["total"] == 2
    assert "ADR 0016" in record["source"]


def test_severity_is_absent_for_another_class_list():
    five = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]
    record = severity_record([(0, 2)], [(0, 2)], five)

    assert record["photograph"] is None
    assert record["group"] is None
    assert "Siltosa" in record["why"]
