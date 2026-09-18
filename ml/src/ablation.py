"""What carries the signal in the descriptor arm? (SPEC 0065)

[SPEC 0044](../../docs/specs/0044-four-arm-e0-feasibility-gate.md) requires the
E0 verdict to report the descriptor arm with each component group removed in
turn. [SPEC 0054](../../docs/specs/0054-the-two-e0-arms-that-do-not-exist-yet.md)
built the machinery — `descriptor_features` takes a `groups` argument — and left
the reporting here.

Each removed group is its own arm, run by `crossval.run_arm` like every other
arm, so a fold is reused rather than recomputed, its partition is verified before
reuse, its cost is recorded and its selection is audited. The four are read as
one diagnostic family paired against the full arm, corrected among themselves and
against nothing else: the gate's own families decide a ship, and a diagnostic
that entered one would move the threshold that decision is read under.

The contrast is `evaluate.one_contrast`, the same implementation the gate uses.
Two copies of one McNemar test is how a diagnostic and a gate come to disagree
about what the same groups say.
"""

from __future__ import annotations

import json
from functools import partial
from pathlib import Path
from types import MappingProxyType
from typing import Callable, Mapping, Sequence

from .descriptors import GROUPS
from .evaluate import one_contrast
from .sensitivity import DESCRIPTOR_PAIR
from .stats import holm_adjust

#: The arm every ablation arm is paired against. Derived from `sensitivity`'s
#: pair rather than spelled again, so the three places that name this arm cannot
#: come to name different ones.
BASE_ARM = DESCRIPTOR_PAIR[0]

#: Where the report lives, beside `d6_sensitivity/` and in the same shape.
ABLATION_DIRNAME = "descriptor_ablation"
ABLATION_REPORT_FILENAME = "ablation.json"

#: The family name these contrasts carry. Not one of `evaluation.contrasts`'
#: families by construction: `evaluate` corrects `primary` and `secondary`
#: separately, and an ablation contrast inside either would spend the correction
#: budget of the family that answers the gate's question.
ABLATION_FAMILY = "ablation"


def ablation_arm_name(group: str) -> str:
    """The arm that is the descriptor arm with `group` removed."""
    return f"{BASE_ARM}_without_{group}"


#: Every ablation arm, mapped to the group it removes. Derived from
#: `descriptors.GROUPS` rather than listed, so a fifth descriptor group arrives
#: with its ablation arm already registered instead of silently unmeasured.
ABLATION_ARMS: Mapping[str, str] = MappingProxyType(
    {ablation_arm_name(group): group for group in GROUPS}
)


def remaining_groups(group: str) -> tuple[str, ...]:
    """Every descriptor group but `group`, in `GROUPS` order.

    Raises:
        ValueError: If `group` is not a descriptor group. Removing a group that
            does not exist would produce an arm identical to the full one, filed
            under a name saying something was taken out of it.
    """
    if group not in GROUPS:
        raise ValueError(
            f"no descriptor group named {group!r}; the groups are "
            f"{', '.join(GROUPS)}"
        )
    return tuple(name for name in GROUPS if name != group)


def ablation_fold_trainer(group: str) -> Callable:
    """The fold trainer for the arm with `group` removed.

    Imported here rather than at module scope, the way `crossval`'s registry
    does it and for the same reason: naming an arm should not pay for the
    imports of the arms beside it, and this module's reading rules have to be
    readable where the arms cannot run.
    """
    from .arms.descriptors import descriptor_features
    from .arms.probe import probe_fold

    return partial(
        probe_fold,
        featuriser=partial(descriptor_features, groups=remaining_groups(group)),
    )


#: The registry entries `crossval` merges into `ARM_TRAINERS`: an arm name to a
#: thunk returning its fold trainer, which is the shape that registry holds.
ABLATION_TRAINERS: Mapping[str, Callable[[], Callable]] = MappingProxyType(
    {arm: partial(ablation_fold_trainer, group) for arm, group in ABLATION_ARMS.items()}
)

#: The predicate, carried in the report so a later reader cannot substitute a
#: different one for the number in front of them.
READING_RULE = (
    "Group-level correctness over the same folds as the full descriptor arm, "
    "paired, compared by the exact McNemar test at evaluation.alpha after Holm "
    "correction within the ablation family alone, with the observed accuracy "
    "difference read against the minimum detectable effect that contrast records "
    "from its own discordance. Both clauses must hold to say a group carries "
    "signal the remaining groups do not replace: significant AND at or above the "
    "minimum detectable effect. Every other combination is recorded as no "
    "measured difference, which is not the same as no difference."
)

#: What the report does not clear, in the report rather than in a reader's head.
LICENCE = (
    "This is a diagnostic over the descriptor arm's own components. No cell of "
    "it is an input to SPEC 0044's decision rule: the ship decision is read on "
    "the four contrasts registered in evaluation.contrasts, and no ablation arm "
    "appears in any of them."
)


def reading_cell(
    *, significant: bool, observed: float, mde: float | None
) -> dict:
    """Which of the rule's four cells one ablation contrast landed in.

    Args:
        significant: Whether the exact McNemar test rejected at ``alpha`` after
            the within-family correction.
        observed: The group-level accuracy difference, signed. Positive favours
            the full arm, which is the removed group having carried something.
        mde: The minimum detectable effect this contrast recorded from its own
            discordance, or ``None`` when no rejection region exists at all —
            which is the experiment saying it can detect nothing, not a
            threshold of zero.
    """
    resolvable = mde is not None and abs(observed) >= mde
    # Three values and not two: a difference of exactly zero has no direction,
    # and naming one states something the number does not.
    if observed > 0:
        favours = "full_arm"
    elif observed < 0:
        favours = "ablated_arm"
    else:
        favours = "neither"

    # The sign is read, not only the magnitude. `carries_signal` is a claim that
    # the group *contributed*, and a resolved difference in the other direction
    # says the opposite — the arm scored better without it. The first draft
    # tested `abs(observed) >= mde` and never looked at the sign it had just
    # computed, so a group whose removal helped was reported as carrying signal,
    # and SPEC 0044's verdict reads that list.
    if significant and resolvable and favours == "full_arm":
        return {
            "cell": "significant_at_or_above_mde",
            "carries_signal": True,
            "favours": favours,
            "reading": (
                "removing this group changed a scored result by more than this "
                "experiment's own floor, so the remaining groups do not replace "
                "what it contributed"
            ),
        }

    if significant and resolvable:
        return {
            "cell": "significant_at_or_above_mde_favouring_the_ablated_arm",
            "carries_signal": False,
            "favours": favours,
            "reading": (
                "the arm scored better without this group by more than this "
                "experiment's own floor. That is not a contribution, and it is "
                "the one cell of this diagnostic that argues for changing the "
                "feature set rather than describing it"
            ),
        }

    if significant:
        return {
            "cell": "significant_below_mde",
            "carries_signal": False,
            "favours": favours,
            "reading": (
                "the test resolves a difference this experiment cannot size: it "
                "is smaller than the measurement's own floor, and a difference "
                "below that floor has not been shown to be one"
            ),
        }

    if resolvable:
        return {
            "cell": "not_significant_at_or_above_mde",
            "carries_signal": False,
            "favours": favours,
            "reading": (
                "a point estimate large enough to matter with a test that cannot "
                "reject it. Nothing is concluded about this group at this number "
                "of sample groups"
            ),
        }

    return {
        "cell": "not_significant_below_mde",
        "carries_signal": False,
        "favours": favours,
        "reading": (
            "removing this group did not measurably change the arm's answer at "
            "this experiment's resolution. Failing to resolve a difference is "
            "not proof of none"
        ),
    }


def read_contrast(contrast: Mapping) -> dict:
    """Apply the rule to one contrast, returning it with its cell attached.

    Read on the corrected p-value where one is present. Reading the raw value
    would make the family it was corrected within a fiction.
    """
    p_value = contrast.get("p_value_holm", contrast["p_value"])
    return {
        **contrast,
        "reading": reading_cell(
            significant=p_value <= contrast["alpha"],
            observed=contrast["observed_difference"],
            mde=contrast["minimum_detectable_effect"],
        ),
    }


def ablation_contrasts(
    correctness: Mapping[str, Mapping[str, bool]],
    *,
    alpha: float,
    power: float,
    absent_reasons: Mapping[str, str] | None = None,
) -> dict:
    """Pair every ablation arm that ran against the full arm, and correct them.

    Args:
        correctness: Group-level correctness per arm name, as
            `evaluate.pooled_group_correctness` returns it. An ablation arm
            absent from it is one that did not run.
        absent_reasons: Why an arm is absent, by arm name, from whoever knew.
            Several different failures reach the same branch — the arm refused
            to run, its folds were refused as a mixed stack, or the operator did
            not ask for it — and a note that said "no predictions were found"
            for all three would describe an integrity failure as an arm nobody
            started. The committed artifact is read where the stderr is gone.

    Returns:
        The computed contrasts and the arms that did not run, the second named
        rather than raised: SPEC 0063 settled that for the gate's own contrasts,
        and a four-hour diagnostic that returns nothing because one arm was
        interrupted is one nobody runs twice.

    Raises:
        ValueError: If the full arm itself is absent. Then there is no pair to
            read at all, and reporting four absences would hide the reason.
    """
    if BASE_ARM not in correctness:
        raise ValueError(
            f"the ablation pairs every arm against {BASE_ARM!r}, which was not "
            f"scored; run it before reading the ablation"
        )

    base = correctness[BASE_ARM]
    reasons = dict(absent_reasons or {})
    contrasts: list[dict] = []
    not_executed: list[dict] = []

    for arm, group in ABLATION_ARMS.items():
        if arm not in correctness:
            not_executed.append(
                {
                    "arm": arm,
                    "group": group,
                    "status": "not_executed",
                    "note": reasons.get(
                        arm,
                        "this arm was not scored, so no contrast was computed "
                        "for it and it is not reported as having lost one",
                    ),
                }
            )
            continue

        contrasts.append(
            one_contrast(
                {
                    "name": f"without_{group}",
                    "family": ABLATION_FAMILY,
                    "arms": [BASE_ARM, arm],
                },
                base,
                correctness[arm],
                alpha,
                power,
            )
        )

    correct_within_family(contrasts)

    return {"contrasts": contrasts, "not_executed": not_executed}


def correct_within_family(contrasts: Sequence[dict]) -> list[dict]:
    """Holm-correct these contrasts as one family, in place, from their raw p-values.

    Over the contrasts it is given, which is what Holm's family is: correcting
    for four when three ran would penalise every one of them for a test nothing
    performed.

    Applied from `p_value` rather than from whatever `p_value_holm` already
    holds, so correcting a merged family is not correcting a correction. That is
    what a split run needs: a contrast carried forward from `--groups lbp`
    carries the Holm value of a family of one, and a report that merged it with
    a second half would present two singly-corrected contrasts as one family of
    two. The reading rule this module carries says the correction is within the
    ablation family, and the family is what the report ends up holding.
    """
    adjusted = holm_adjust([contrast["p_value"] for contrast in contrasts])
    for contrast, value in zip(contrasts, adjusted):
        contrast["p_value_holm"] = value
        contrast["family_size"] = len(contrasts)
    return list(contrasts)


def write_ablation_report(
    directory: Path | str,
    *,
    version: str,
    manifest_digest: str,
    contrasts: Sequence[Mapping],
    not_executed: Sequence[Mapping],
    seeds: Mapping,
    runtimes: Mapping[str, Mapping | None],
    costs: Mapping[str, Mapping] | None = None,
) -> dict:
    """Write the diagnostic, whichever way it reads.

    Committed either way and with everything needed to reproduce it: an ablation
    that reported only when it found something would be one nobody could read a
    null from.

    Args:
        runtimes: What each arm's own folds recorded, read back from the
            artifacts rather than taken from the reporting process, so a report
            written on one machine cannot describe an arm that ran on another.
        costs: What each arm's folds recorded spending, summed from their own
            `cost.json`. SPEC 0065 accepts that an ablation run beside another
            arm records contention as its own time, on condition that the report
            says what it observed; `runtimes` carries the device and the library
            versions and no timing at all, so without this the condition is
            unmet.
    """
    read = [read_contrast(contrast) for contrast in contrasts]

    report = {
        "spec": "0065",
        "dataset_version": version,
        "manifest_digest": manifest_digest,
        "base_arm": BASE_ARM,
        "groups": list(GROUPS),
        "reading_rule": READING_RULE,
        "licence": LICENCE,
        "contrasts": read,
        "not_executed": [dict(entry) for entry in not_executed],
        "carries_signal": [
            entry["name"] for entry in read if entry["reading"]["carries_signal"]
        ],
        "seeds": dict(seeds),
        "runtimes": {
            arm: dict(runtime) if runtime else None
            for arm, runtime in runtimes.items()
        },
        "costs": {arm: dict(cost) for arm, cost in (costs or {}).items()},
        "cost_note": (
            "wall clock as each arm's own folds recorded it, contention "
            "included. An arm that ran beside another on this machine recorded "
            "the contention as its own time, and this is the figure observed "
            "rather than a corrected one"
        ),
    }

    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / ABLATION_REPORT_FILENAME).write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return report
