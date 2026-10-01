"""How far a stored distribution can be trusted (SPEC 0095, #188), and what
`calibration_study` fits and compares to improve it (SPEC 0098).

Pure functions over labels and probability vectors, so they run wherever
`evaluate.py` runs: no model, no TensorFlow. `evaluate.arm_metrics` calls them
on each repeat's pooled photographs and writes what they return into
`metrics.json`.

The level is the photograph, because the app shows one photograph's
distribution. No function here returns an interval. Photographs of one sample
are not independent, so an interval on a photograph count would overstate the
evidence, and these figures describe a run rather than estimate a population.
"""

from __future__ import annotations

import math
from typing import Mapping, Sequence

import numpy as np

PERCENTILES = (10, 50, 90)

#: Equal-width bins of the top-1 probability on [0, 1]. The expected calibration
#: error depends on the count, so the count is written beside every error.
CALIBRATION_BINS = 10

#: Where the sweeps cut. The top-1 grid starts at chance for four classes; the
#: margin grid starts at no margin at all.
TOP1_THRESHOLDS = tuple(round(0.25 + 0.05 * step, 2) for step in range(15))
MARGIN_THRESHOLDS = tuple(round(0.05 * step, 2) for step in range(19))

#: A figure within this of a threshold or a bin edge counts as reaching it, so
#: a decimal cut such as 0.05 is not lost to binary rounding: 0.35 - 0.30 is
#: 0.04999... in floating point.
_EDGE_TOLERANCE = 1e-9

#: ADR 0016's ordering of the confusions over the model's four classes,
#: symmetric. It is an ordering and not a set of weights: no one supplied the
#: numbers, so none are invented here.
SEVERITY_TIERS = ("most_serious", "serious", "moderate", "mild")
SEVERITY = {
    frozenset({"Arenosa", "Muito Argilosa"}): "most_serious",
    frozenset({"Arenosa", "Argilosa"}): "serious",
    frozenset({"Media", "Muito Argilosa"}): "serious",
    frozenset({"Arenosa", "Media"}): "moderate",
    frozenset({"Media", "Argilosa"}): "moderate",
    frozenset({"Argilosa", "Muito Argilosa"}): "mild",
}
SEVERITY_CLASSES = frozenset().union(*SEVERITY)
SEVERITY_SOURCE = (
    "Confusions counted by ADR 0016's ordering, which the project owner approved "
    "on 2026-08-25. It ranks the confusions and gives no weights, so none are "
    "applied. Pooled over repeats, as the confusion matrix is."
)


def _top(distribution: Sequence[float]) -> tuple[float, float, int]:
    """The top-1 probability, its margin over the second, and the class."""
    order = sorted(range(len(distribution)), key=lambda i: -distribution[i])
    first, second = order[0], order[1]
    return (
        float(distribution[first]),
        float(distribution[first] - distribution[second]),
        first,
    )


def percentiles(values: Sequence[float]) -> dict:
    """The 10th, 50th and 90th percentiles, by numpy's linear interpolation."""
    return {
        f"p{p}": float(np.percentile(np.asarray(values, dtype=float), p))
        for p in PERCENTILES
    }


def calibration_error(
    labels: Sequence[int],
    distributions: Sequence[Sequence[float]],
    bins: int = CALIBRATION_BINS,
) -> dict:
    """The expected calibration error and the reliability curve behind it.

    Bin i holds top-1 probabilities in [i / bins, (i + 1) / bins), and the last
    bin also holds 1. The error weighs each bin's gap between accuracy and mean
    top-1 probability by its share of photographs. An empty bin has no mean and
    no accuracy, and says so with null rather than with 0.
    """
    counts = [0] * bins
    confidence_sums = [0.0] * bins
    correct = [0] * bins
    for label, distribution in zip(labels, distributions):
        top1, _, predicted = _top(distribution)
        index = min(math.floor(top1 * bins + _EDGE_TOLERANCE), bins - 1)
        counts[index] += 1
        confidence_sums[index] += top1
        correct[index] += int(predicted == int(label))

    total = sum(counts)
    curve = []
    error = 0.0
    for index in range(bins):
        count = counts[index]
        mean = confidence_sums[index] / count if count else None
        accuracy = correct[index] / count if count else None
        if count:
            error += count / total * abs(accuracy - mean)
        curve.append(
            {
                "low": index / bins,
                "high": (index + 1) / bins,
                "count": count,
                "mean_confidence": mean,
                "accuracy": accuracy,
            }
        )
    return {
        "bins": bins,
        "expected_calibration_error": error if total else None,
        "reliability": curve,
    }


def _sweep_points(
    scored: Sequence[tuple[float, bool]], thresholds: Sequence[float]
) -> list[dict]:
    """Coverage and accuracy among the covered, at each threshold.

    With nothing to cover there is no coverage to state, and with nothing
    covered there is no accuracy: both are null, never 0.
    """
    points = []
    for threshold in thresholds:
        covered = [right for figure, right in scored if figure >= threshold - _EDGE_TOLERANCE]
        points.append(
            {
                "threshold": threshold,
                "covered": len(covered),
                "coverage": len(covered) / len(scored) if scored else None,
                "accuracy": sum(covered) / len(covered) if covered else None,
            }
        )
    return points


def coverage_sweep(
    labels: Sequence[int],
    distributions: Sequence[Sequence[float]],
    classes: Sequence[str],
) -> dict:
    """What refusing uncertain photographs leaves, on the top-1 and the margin.

    Reported overall and per predicted class, since a per-class band would be
    keyed by the class the app names (#243). A per-class record rests on a
    handful of groups, so it carries the flag `per_class` carries.
    """
    tops = [(_top(d), int(label)) for label, d in zip(labels, distributions)]

    def axis(figure: int, thresholds: Sequence[float]) -> dict:
        scored = [(top[figure], top[2] == label) for top, label in tops]
        return {
            "thresholds": list(thresholds),
            "overall": _sweep_points(scored, thresholds),
            "per_predicted_class": {
                name: {
                    "headline": False,
                    "why": (
                        "a per-class sweep rests on the few groups predicted as "
                        "that class and is a diagnostic, not a result (#197)"
                    ),
                    "photographs": sum(1 for top, _ in tops if top[2] == index),
                    "points": _sweep_points(
                        [
                            (top[figure], top[2] == label)
                            for top, label in tops
                            if top[2] == index
                        ],
                        thresholds,
                    ),
                }
                for index, name in enumerate(classes)
            },
        }

    return {"top1": axis(0, TOP1_THRESHOLDS), "margin": axis(1, MARGIN_THRESHOLDS)}


def confidence_record(
    labels: Sequence[int],
    distributions: Sequence[Sequence[float]],
    groups: Sequence[str],
    classes: Sequence[str],
) -> dict:
    """Every confidence figure for one pool of photographs, with its support."""
    tops = [_top(distribution) for distribution in distributions]
    return {
        "level": "photograph",
        "photographs": len(distributions),
        "groups": len(set(groups)),
        "top1": percentiles([top[0] for top in tops]),
        "margin": percentiles([top[1] for top in tops]),
        "calibration": calibration_error(labels, distributions),
        "sweep": coverage_sweep(labels, distributions, classes),
    }


def _severity_counts(
    pairs: Sequence[tuple[int, int]], classes: Sequence[str]
) -> dict:
    counts = {"total": len(pairs), "correct": 0, **{tier: 0 for tier in SEVERITY_TIERS}}
    for truth, predicted in pairs:
        if truth == predicted:
            counts["correct"] += 1
        else:
            counts[SEVERITY[frozenset({classes[truth], classes[predicted]})]] += 1
    return counts


def severity_record(
    photograph_pairs: Sequence[tuple[int, int]],
    group_pairs: Sequence[tuple[int, int]],
    classes: Sequence[str],
) -> Mapping:
    """Confusions counted by ADR 0016's tier, at both levels.

    Null, with the reason, when the classes are not the four the ordering
    covers: a confusion it does not rank cannot be placed in a tier.
    """
    if set(classes) != SEVERITY_CLASSES:
        return {
            "source": SEVERITY_SOURCE,
            "photograph": None,
            "group": None,
            "why": (
                f"the classes {list(classes)} are not the four ADR 0016 orders "
                f"({sorted(SEVERITY_CLASSES)}), so a confusion cannot be placed "
                "in a tier"
            ),
        }
    return {
        "source": SEVERITY_SOURCE,
        "photograph": _severity_counts(photograph_pairs, classes),
        "group": _severity_counts(group_pairs, classes),
    }


# --- SPEC 0098: what the calibration study fits and compares -----------------

#: The temperature fit searches 1/T over this range, from a twentyfold
#: flattening to a twentyfold sharpening of the log-probabilities.
_INVERSE_TEMPERATURE_BOUNDS = (0.05, 20.0)
_GOLDEN_TOLERANCE = 1e-10
#: A zero probability has no logarithm. The floor keeps it negligible rather
#: than infinite, and changes nothing a stored distribution carries.
_PROBABILITY_FLOOR = 1e-12

#: ADR 0011's constants, as `ClassificationVerdict` declares them in Dart.
ADR0011_CONCLUSIVE_MARGIN = 0.15
ADR0011_CONCLUSIVE_TOP_SHARE = 0.50
ADR0011_AMBIGUOUS_PAIR_SHARE = 0.65


def apply_temperature(distribution: Sequence[float], temperature: float) -> list[float]:
    """The distribution with p(y) raised to 1/T and renormalised.

    That is temperature scaling with the log-probabilities as logits. It keeps
    the order of the classes, so it moves the probabilities and never the
    argmax.
    """
    logs = [math.log(max(float(p), _PROBABILITY_FLOOR)) / temperature for p in distribution]
    top = max(logs)
    weights = [math.exp(value - top) for value in logs]
    total = sum(weights)
    return [weight / total for weight in weights]


def _negative_log_likelihood(
    labels: Sequence[int], distributions: Sequence[Sequence[float]], temperature: float
) -> float:
    return -sum(
        math.log(max(apply_temperature(distribution, temperature)[int(label)], _PROBABILITY_FLOOR))
        for label, distribution in zip(labels, distributions)
    )


def fit_temperature(
    labels: Sequence[int], distributions: Sequence[Sequence[float]]
) -> float:
    """The temperature that minimises the negative log-likelihood.

    The likelihood is convex in 1/T, so a golden-section search over
    `_INVERSE_TEMPERATURE_BOUNDS` finds it, deterministically and with no
    optimiser dependency. A temperature below 1 sharpens the distribution.
    """
    low, high = _INVERSE_TEMPERATURE_BOUNDS
    ratio = (math.sqrt(5) - 1) / 2

    def cost(inverse: float) -> float:
        return _negative_log_likelihood(labels, distributions, 1.0 / inverse)

    left = high - ratio * (high - low)
    right = low + ratio * (high - low)
    cost_left, cost_right = cost(left), cost(right)
    while high - low > _GOLDEN_TOLERANCE:
        if cost_left <= cost_right:
            high, right, cost_right = right, left, cost_left
            left = high - ratio * (high - low)
            cost_left = cost(left)
        else:
            low, left, cost_left = left, right, cost_right
            right = low + ratio * (high - low)
            cost_right = cost(right)
    return 1.0 / ((low + high) / 2)


def conformal_threshold(scores: Sequence[float], alpha: float) -> float:
    """The split-conformal threshold at level `alpha`.

    It is the ceil((n + 1)(1 - alpha))-th smallest of the n calibration scores.
    When that rank exceeds n, no finite threshold carries the guarantee, so it
    is infinite and every class is admitted. The rank is taken a hair below its
    product, so a level such as 0.2 is not pushed one rank up by binary
    rounding.
    """
    n = len(scores)
    rank = max(math.ceil((n + 1) * (1 - alpha) - _EDGE_TOLERANCE), 1)
    if rank > n:
        return math.inf
    return float(sorted(scores)[rank - 1])


def conformal_set(distribution: Sequence[float], threshold: float) -> list[int]:
    """The classes whose score 1 - p reaches no further than `threshold`."""
    floor = 1.0 - threshold - _EDGE_TOLERANCE
    return [index for index, p in enumerate(distribution) if p >= floor]


def verdict_of_set(size: int) -> str:
    """ADR 0011's verdict for a prediction set of `size` classes (#193)."""
    if size == 1:
        return "conclusive"
    if size == 2:
        return "ambiguous"
    return "insufficient"


def adr0011_verdict(distribution: Sequence[float]) -> tuple[str, list[int]]:
    """ADR 0011's verdict, and the classes it asserts.

    The rule is `ClassificationVerdict.fromDistribution`'s, scan included, with
    no tolerance, because the Dart factory has none and the two must agree on
    every double. A conclusive verdict asserts the top-1, an ambiguous one the
    top two, and an insufficient one asserts nothing, which reads as every
    class.
    """
    top, runner_up = -math.inf, -math.inf
    top_index = runner_up_index = None
    for index, p in enumerate(distribution):
        if p > top:
            runner_up, runner_up_index = top, top_index
            top, top_index = p, index
        elif p > runner_up:
            runner_up, runner_up_index = p, index
    if runner_up_index is None:
        runner_up = 0.0
    margin = top - runner_up
    if margin >= ADR0011_CONCLUSIVE_MARGIN and top >= ADR0011_CONCLUSIVE_TOP_SHARE:
        return "conclusive", [top_index]
    if margin < ADR0011_CONCLUSIVE_MARGIN and top + runner_up >= ADR0011_AMBIGUOUS_PAIR_SHARE:
        return "ambiguous", [top_index, runner_up_index]
    return "insufficient", list(range(len(distribution)))
