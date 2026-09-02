"""The uncertainty arithmetic of the evaluation protocol (SPEC 0042).

Everything here is pure stdlib and NumPy, and nothing in it imports TensorFlow.
That is deliberate. The interval and the minimum detectable effect are the
outputs the protocol exists to record, and a figure that can only be recomputed
on a machine carrying the training stack is a figure most readers cannot check.
It also means these functions run in CI and on a collector's laptop alike.

Two rules the module encodes rather than merely serves:

- **The unit is the sample group.** Every interval and every paired contrast is
  computed over groups, because photographs of one physical sample are not
  independent and counting them would overstate the evidence
  (:func:`group_level_predictions` is how a group's prediction is formed).
- **The spread across folds is never an interval.** Fold test sides are disjoint
  and small, so their spread understates the interval on the pooled figure
  (Varoquaux 2018, *NeuroImage* 180:68-77). :func:`wilson_interval` on the
  pooled group count is what carries sampling variance; the spread across
  repeats carries training variance. Neither is the fold spread.
"""

from __future__ import annotations

import math
from statistics import NormalDist
from typing import Mapping, Sequence

import numpy as np

#: Two-sided significance level and power the protocol reports against, per
#: ADR 0020. Callers pass their configured values; these are the defaults the
#: spec fixes so a call site cannot quietly report against a weaker test.
DEFAULT_ALPHA = 0.05
DEFAULT_POWER = 0.80

#: Bisection depth for the minimum detectable effect. Power is a polynomial in
#: the discordant split, so 60 halvings resolve the effect far below the
#: precision anything downstream reports it at.
_BISECTION_STEPS = 60


def wilson_interval(
    successes: int, total: int, confidence: float = 0.95
) -> tuple[float, float]:
    """Return the Wilson score interval for a proportion.

    Chosen over the normal approximation because the counts here are small — 77
    groups, and fewer inside a class — and the approximation's interval leaves
    the unit range and collapses to zero width at 0 or 100 % correct, both of
    which would misreport exactly the cases this protocol has to report.

    Args:
        successes: Number of correct group predictions.
        total: Number of groups scored. Must be at least one.
        confidence: Two-sided coverage, 0.95 unless a caller says otherwise.

    Returns:
        The (lower, upper) bound, each within [0, 1].

    Raises:
        ValueError: If ``total`` is not positive or ``successes`` is out of range.
    """
    if total < 1:
        raise ValueError(
            f"a Wilson interval needs at least one observation, got total={total}"
        )
    if not 0 <= successes <= total:
        raise ValueError(
            f"successes must lie in [0, {total}], got {successes}"
        )
    if not 0 < confidence < 1:
        raise ValueError(f"confidence must lie in (0, 1), got {confidence}")

    z = NormalDist().inv_cdf(1 - (1 - confidence) / 2)
    proportion = successes / total
    denominator = 1 + z**2 / total
    centre = (proportion + z**2 / (2 * total)) / denominator
    spread = (
        z
        / denominator
        * math.sqrt(
            proportion * (1 - proportion) / total + z**2 / (4 * total**2)
        )
    )
    return (max(0.0, centre - spread), min(1.0, centre + spread))


def mcnemar_exact_p_value(favouring_first: int, favouring_second: int) -> float:
    """Two-sided exact McNemar p-value for a pair of discordant counts.

    Exact rather than the chi-square approximation with or without continuity
    correction: at 77 groups the discordant count is routinely below the twenty
    the approximation needs, and the approximation is anti-conservative there.

    The test conditions on the number of discordant pairs and asks whether they
    split evenly, so the p-value is the two-sided binomial tail at 0.5.

    Args:
        favouring_first: Pairs the first arm got right and the second wrong.
        favouring_second: Pairs the second arm got right and the first wrong.

    Returns:
        The p-value, capped at 1.0. Exactly 1.0 when nothing is discordant,
        which reads as "no evidence" rather than as a missing value.

    Raises:
        ValueError: If either count is negative.
    """
    if favouring_first < 0 or favouring_second < 0:
        raise ValueError(
            "discordant counts must be non-negative, got "
            f"{favouring_first} and {favouring_second}"
        )

    discordant = favouring_first + favouring_second
    if discordant == 0:
        return 1.0

    smaller = min(favouring_first, favouring_second)
    tail = sum(_binomial_pmf(i, discordant, 0.5) for i in range(smaller + 1))
    return min(1.0, 2 * tail)


def mcnemar_minimum_detectable_effect(
    pairs: int,
    discordant_rate: float,
    alpha: float = DEFAULT_ALPHA,
    power: float = DEFAULT_POWER,
) -> float | None:
    """Smallest accuracy difference the exact McNemar test would find.

    The calculation is the standard exact-binomial power calculation on
    discordant pairs, and it is worth stating in full because every reported
    difference is read against it.

    Let ``n`` be the number of paired groups and ``r`` the observed discordant
    rate, so the expected number of discordant pairs is ``d = round(n * r)``.
    McNemar conditions on ``d`` and tests whether the discordant pairs split
    evenly, so the test is a two-sided exact binomial test of ``psi = 0.5``,
    where ``psi`` is the share of discordant pairs favouring the first arm. Its
    rejection region at level ``alpha`` is ``{x <= c} u {x >= d - c}`` for the
    largest ``c`` with ``2 * P(X <= c | d, 0.5) <= alpha``.

    The difference in accuracy that ``psi`` corresponds to is

        delta = (favouring_first - favouring_second) / n = r * (2 * psi - 1)

    so the minimum detectable effect is ``r * (2 * psi* - 1)`` for the smallest
    ``psi*`` whose exact power reaches the requested level:

        power(psi) = P(X <= c | d, psi) + P(X >= d - c | d, psi)

    Args:
        pairs: Number of paired sample groups.
        discordant_rate: Observed share of pairs on which the two arms disagree.
        alpha: Two-sided significance level.
        power: Power the effect must reach.

    Returns:
        The minimum detectable difference in group-level accuracy, or ``None``
        when no rejection region exists at ``alpha`` for the observed number of
        discordant pairs — that is, when no effect of any size is detectable.
        ``None`` is returned rather than a large number because the two are
        different facts and a consumer must be able to tell them apart.

    Raises:
        ValueError: If any argument is outside its permitted range.
    """
    if pairs < 1:
        raise ValueError(f"pairs must be at least one, got {pairs}")
    if not 0 <= discordant_rate <= 1:
        raise ValueError(
            f"discordant_rate must lie in [0, 1], got {discordant_rate}"
        )
    if not 0 < alpha < 1:
        raise ValueError(f"alpha must lie in (0, 1), got {alpha}")
    if not 0 < power < 1:
        raise ValueError(f"power must lie in (0, 1), got {power}")

    discordant = int(round(pairs * discordant_rate))
    critical = _rejection_boundary(discordant, alpha)
    if critical is None:
        return None

    low, high = 0.5, 1.0
    for _ in range(_BISECTION_STEPS):
        middle = (low + high) / 2
        if _exact_power(discordant, middle, critical) >= power:
            high = middle
        else:
            low = middle

    return discordant_rate * (2 * high - 1)


def holm_adjust(p_values: Sequence[float]) -> list[float]:
    """Holm step-down adjusted p-values, returned in the input order.

    Holm rather than Bonferroni because it is uniformly more powerful at the
    same familywise error rate, and the family here is small enough that the
    difference is the difference between a contrast clearing and not.
    """
    if not p_values:
        return []
    for value in p_values:
        if not 0 <= value <= 1:
            raise ValueError(f"p-values must lie in [0, 1], got {value}")

    family_size = len(p_values)
    order = sorted(range(family_size), key=lambda index: p_values[index])
    adjusted = [0.0] * family_size
    running = 0.0
    for rank, index in enumerate(order):
        running = max(running, (family_size - rank) * p_values[index])
        adjusted[index] = min(1.0, running)
    return adjusted


def group_level_predictions(
    distributions_by_group: Mapping[str, Sequence[Sequence[float]]],
) -> dict[str, int]:
    """Reduce each group's photograph distributions to one predicted class.

    The rule is the mean of the distributions, argmaxed — not a vote over the
    photographs' own argmaxes. A vote discards how confident each photograph
    was, so two photographs that barely prefer one class outrank one that is
    certain of another; averaging the distributions keeps that information,
    which at two or three photographs per sample is most of it.

    Args:
        distributions_by_group: Group id to that group's per-photograph class
            distributions.

    Returns:
        Group id to predicted class index.

    Raises:
        ValueError: If a group carries no photograph.
    """
    predictions: dict[str, int] = {}
    for group_id, distributions in distributions_by_group.items():
        if len(distributions) == 0:
            raise ValueError(
                f"group {group_id!r} has no photograph, so it has no prediction"
            )
        mean = np.mean(np.asarray(distributions, dtype=np.float64), axis=0)
        predictions[group_id] = int(np.argmax(mean))
    return predictions


def _rejection_boundary(discordant: int, alpha: float) -> int | None:
    """Largest ``c`` whose two-sided exact tail is still within ``alpha``.

    ``None`` when even the most extreme split cannot reject, which is the
    small-sample case the protocol has to report rather than round away.
    """
    boundary: int | None = None
    for count in range(discordant + 1):
        tail = sum(_binomial_pmf(i, discordant, 0.5) for i in range(count + 1))
        if 2 * tail <= alpha:
            boundary = count
        else:
            break
    return boundary


def _exact_power(discordant: int, favouring: float, critical: int) -> float:
    """Probability of landing in the rejection region at a given split."""
    lower = sum(
        _binomial_pmf(i, discordant, favouring) for i in range(critical + 1)
    )
    upper = sum(
        _binomial_pmf(i, discordant, favouring)
        for i in range(discordant - critical, discordant + 1)
    )
    return lower + upper


def _binomial_pmf(successes: int, trials: int, probability: float) -> float:
    """Binomial probability mass, by exact integer coefficients.

    SciPy is not a dependency of this pipeline and is not being added for one
    distribution: `ml/requirements.txt` pins what the training stack needs, and
    `math.comb` is exact where a floating-point gamma function is not.
    """
    return (
        math.comb(trials, successes)
        * probability**successes
        * (1 - probability) ** (trials - successes)
    )
