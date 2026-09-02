"""Tests for the uncertainty arithmetic of SPEC 0042.

Every function under test is pure numpy/stdlib, so the protocol's uncertainty
can be checked on a machine that cannot install TensorFlow. That is not a
convenience: the interval and the minimum detectable effect are what the
protocol exists to record, and a number nobody can recompute is not a record.
"""

import math

import pytest

from src.stats import (
    group_level_predictions,
    holm_adjust,
    mcnemar_exact_p_value,
    mcnemar_minimum_detectable_effect,
    wilson_interval,
)


# --- Wilson interval -------------------------------------------------------


def test_wilson_interval_matches_the_published_value():
    """5 of 10 at 95 % is (0.2366, 0.7634) in every published table."""
    low, high = wilson_interval(5, 10)

    assert low == pytest.approx(0.2366, abs=1e-4)
    assert high == pytest.approx(0.7634, abs=1e-4)


def test_wilson_interval_brackets_the_point_estimate():
    low, high = wilson_interval(60, 77)

    assert low < 60 / 77 < high


def test_wilson_interval_never_leaves_the_unit_range():
    """The score interval is what is used precisely because it cannot."""
    assert wilson_interval(0, 20)[0] == pytest.approx(0.0, abs=1e-12)
    assert wilson_interval(20, 20)[1] == pytest.approx(1.0, abs=1e-12)


def test_wilson_interval_refuses_an_empty_denominator():
    with pytest.raises(ValueError, match="at least one"):
        wilson_interval(0, 0)


def test_wilson_interval_narrows_as_the_count_grows():
    """The interval is a function of the count, which is the point of using it."""
    narrow = wilson_interval(77, 154)
    wide = wilson_interval(6, 12)

    assert (narrow[1] - narrow[0]) < (wide[1] - wide[0])


# --- exact McNemar ---------------------------------------------------------


def test_mcnemar_exact_matches_the_binomial_by_hand():
    """b=1, c=9 gives 2 * P(X <= 1) for X ~ Binomial(10, 0.5) = 22/1024."""
    assert mcnemar_exact_p_value(1, 9) == pytest.approx(22 / 1024)


def test_mcnemar_exact_is_symmetric_in_its_two_counts():
    assert mcnemar_exact_p_value(3, 11) == mcnemar_exact_p_value(11, 3)


def test_mcnemar_exact_returns_one_without_discordance():
    """No discordant pair is no evidence, not a missing value."""
    assert mcnemar_exact_p_value(0, 0) == 1.0


def test_mcnemar_exact_is_capped_at_one():
    assert mcnemar_exact_p_value(5, 5) == 1.0


def test_mcnemar_exact_refuses_a_negative_count():
    with pytest.raises(ValueError, match="non-negative"):
        mcnemar_exact_p_value(-1, 4)


# --- minimum detectable effect ---------------------------------------------


def test_mde_falls_as_the_pair_count_rises():
    """The whole reason k-fold replaces the single split.

    Twelve groups — the single split's test side — is below the size at which
    any effect is detectable at all, so the comparison starts above it.
    """
    assert mcnemar_minimum_detectable_effect(12, 0.3) is None

    forty = mcnemar_minimum_detectable_effect(40, 0.3)
    seventy_seven = mcnemar_minimum_detectable_effect(77, 0.3)

    assert forty > seventy_seven


def test_mde_is_computed_from_the_observed_discordant_rate():
    """A different observed discordance gives a different floor, from the data."""
    sparse = mcnemar_minimum_detectable_effect(77, 0.1)
    dense = mcnemar_minimum_detectable_effect(77, 0.5)

    assert sparse != dense
    assert 0.0 < sparse <= 0.1
    assert 0.0 < dense <= 0.5


def test_mde_never_exceeds_the_discordant_rate():
    """A paired difference cannot exceed the share of pairs that disagree."""
    rate = 0.25
    assert mcnemar_minimum_detectable_effect(77, rate) <= rate + 1e-12


def test_mde_is_none_when_no_rejection_region_exists():
    """Five discordant pairs cannot reject at 0.05, so no effect is detectable."""
    assert mcnemar_minimum_detectable_effect(10, 0.4) is None


def test_mde_reaches_eighty_percent_power_at_the_reported_effect():
    """The returned effect is the smallest one the test would find, not a guess."""
    pairs, rate = 77, 0.3
    effect = mcnemar_minimum_detectable_effect(pairs, rate)

    discordant = round(pairs * rate)
    favouring = 0.5 + effect / (2 * rate)
    assert _exact_power(discordant, favouring, alpha=0.05) >= 0.80

    smaller = 0.5 + (effect - 0.01) / (2 * rate)
    assert _exact_power(discordant, smaller, alpha=0.05) < 0.80


def _exact_power(discordant: int, favouring: float, alpha: float) -> float:
    """Power of the two-sided exact binomial test, recomputed independently."""
    critical = -1
    for count in range(discordant + 1):
        tail = sum(_pmf(i, discordant, 0.5) for i in range(count + 1))
        if 2 * tail <= alpha:
            critical = count
    if critical < 0:
        return 0.0
    lower = sum(_pmf(i, discordant, favouring) for i in range(critical + 1))
    upper = sum(
        _pmf(i, discordant, favouring)
        for i in range(discordant - critical, discordant + 1)
    )
    return lower + upper


def _pmf(successes: int, trials: int, probability: float) -> float:
    return (
        math.comb(trials, successes)
        * probability**successes
        * (1 - probability) ** (trials - successes)
    )


def test_mde_refuses_a_rate_outside_the_unit_range():
    with pytest.raises(ValueError, match="discordant_rate"):
        mcnemar_minimum_detectable_effect(77, 1.4)


# --- Holm ------------------------------------------------------------------


def test_holm_adjust_scales_the_smallest_p_by_the_family_size():
    adjusted = holm_adjust([0.01, 0.04, 0.03])

    assert adjusted[0] == pytest.approx(0.03)


def test_holm_adjust_is_monotone_in_the_original_order():
    """Holm's step-down enforces a running maximum; a dip would be a defect."""
    adjusted = holm_adjust([0.01, 0.02, 0.03, 0.04])
    ordered = sorted(zip([0.01, 0.02, 0.03, 0.04], adjusted))

    running = 0.0
    for _, value in ordered:
        assert value >= running - 1e-12
        running = value


def test_holm_adjust_caps_every_value_at_one():
    assert all(value <= 1.0 for value in holm_adjust([0.4, 0.5, 0.9]))


def test_holm_adjust_of_one_p_value_is_that_p_value():
    assert holm_adjust([0.02]) == [0.02]


def test_holm_adjust_of_an_empty_family_is_empty():
    assert holm_adjust([]) == []


# --- group-level aggregation -----------------------------------------------


def test_group_prediction_is_the_argmax_of_the_mean_not_a_photograph_vote():
    """The two disagree, which is why the rule has to be stated.

    Two photographs weakly prefer class 0 and one strongly prefers class 1. A
    majority vote over photographs says 0; the mean of the distributions says 1.
    """
    distributions = {
        "Arenosa::S1": [
            [0.51, 0.49],
            [0.51, 0.49],
            [0.02, 0.98],
        ]
    }

    assert group_level_predictions(distributions) == {"Arenosa::S1": 1}


def test_group_prediction_refuses_a_group_with_no_photograph():
    with pytest.raises(ValueError, match="no photograph"):
        group_level_predictions({"Arenosa::S1": []})
