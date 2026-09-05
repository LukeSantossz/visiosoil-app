"""Does the transported population change the answer? (SPEC 0057)

SPEC 0055's probe demonstrated that the capture population is **recoverable**
from the patches the texture arms see. Recoverable is not exploited, and nothing
in the record separated the two: the probe's finding is that the information is
present in the representation, not that an arm uses it.

This module reads the experiment that separates them. Two arms are run over
**one partition** — with population `B` in their training sides as SPEC 0040 D6
permits, and without — and the pair is compared on the groups D6 protects. The
partition is untouched by construction, which is what makes the contrast paired
and what makes the runs reusable by the E0 gate afterwards.

The reading rule is fixed in SPEC 0057 and applied here. It is exhaustive over
four cells rather than defined on the two that are easy to describe, because a
report with no branch to take hands ADR 0021 an undefined input.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Mapping, Sequence

from .evaluate import one_contrast
from .manifest import TRAIN_ONLY_SOURCE_GROUPS

#: The population D6 restricts to training, and therefore the one withheld.
#: Derived from the manifest's constant rather than spelled again, so the two
#: cannot drift: if D6 ever restricted a second population, this would refuse
#: rather than silently measure one of them.
(WITHHELD_POPULATION,) = sorted(TRAIN_ONLY_SOURCE_GROUPS)

#: The two pairs. The first of each is the arm as the E0 gate would run it; the
#: second is the same arm with `B` out of its own training side.
DESCRIPTOR_PAIR = ("descriptors", f"descriptors_without_{WITHHELD_POPULATION.lower()}")
CNN_PAIR = ("cnn", f"cnn_without_{WITHHELD_POPULATION.lower()}")

#: Bound by name so a test can assert the identity. Two implementations of one
#: contrast is how the sensitivity result and the gate's own contrasts come to
#: disagree about what a McNemar test on these groups says.
_CONTRAST_IMPLEMENTATION = one_contrast

SENSITIVITY_REPORT_FILENAME = "sensitivity.json"

#: The predicate, in the words SPEC 0057 fixed, carried in the report so a later
#: reader cannot substitute a different one for the number in front of them.
READING_RULE = (
    "Group-level correctness on the groups D6 protects, paired, compared by the "
    "exact McNemar test at evaluation.alpha, with the observed accuracy "
    "difference read against the minimum detectable effect that contrast records "
    "from its own discordance. Both clauses must hold to call it a difference: "
    "significant AND at or above the minimum detectable effect re-opens SPEC 0040 "
    "D6; every other combination leaves it standing. The three combinations that "
    "leave it standing are not one finding, and only one of them is a clean null "
    "— the report names which cell it landed in. Each arm's pair is read on its "
    "own and neither is pooled with nor corrected against the other, so D6 is "
    "re-opened if either lands in the top row."
)

#: What the sensitivity does and does not clear, carried beside the numbers so
#: the E0 verdict cannot cite it as a general clearance.
LICENCE = (
    "Measured on the descriptor arm and on the incumbent CNN, each with and "
    "without the withheld population in its training side. It does not clear the "
    "frozen-encoder arm, which was not run in either configuration and which "
    "SPEC 0044 permits to be recorded as not executed."
)


def reading_cell(
    *, significant: bool, observed: float, mde: float | None
) -> dict:
    """Which of the rule's four cells a contrast landed in.

    Args:
        significant: Whether the exact McNemar test rejected at ``alpha``.
        observed: The group-level accuracy difference, signed. Positive favours
            the arm that kept the withheld population in training.
        mde: The minimum detectable effect this contrast recorded from its own
            discordance, or ``None`` when no rejection region exists at all —
            which is the experiment saying it can detect nothing, not a
            threshold of zero.

    Returns:
        The cell's name, whether D6 stands or is re-opened, whether the reading
        is a demonstrated absence rather than a failure to resolve, which arm
        the difference favours, and the sentence the report prints.
    """
    resolvable = mde is not None and abs(observed) >= mde
    favours = "with_withheld" if observed > 0 else "without_withheld"

    if significant and resolvable:
        return {
            "cell": "significant_at_or_above_mde",
            "d6": "re-opened",
            "demonstrated_absence": False,
            "favours": favours,
            "reading": (
                "the withheld population's presence in training changes a scored "
                "result, so SPEC 0040 D6 does not neutralise it. The ADR takes "
                "the decision with the size and sign of the change in hand"
            ),
        }

    if significant:
        return {
            "cell": "significant_below_mde",
            "d6": "stands",
            "demonstrated_absence": False,
            "favours": favours,
            "reading": (
                "the test resolves a difference this experiment cannot size: it "
                "is smaller than the measurement's own floor, and a difference "
                "below that floor has not been shown to be one. D6 stands, and "
                "this is not evidence that the effect is absent"
            ),
        }

    if resolvable:
        return {
            "cell": "not_significant_at_or_above_mde",
            "d6": "stands",
            "demonstrated_absence": False,
            "favours": favours,
            "reading": (
                "a point estimate large enough to matter with a test that cannot "
                "reject it. D6 stands, and this is the combination that most "
                "argues for more sample groups — which ADR 0016 records this "
                "dataset will never supply"
            ),
        }

    return {
        "cell": "not_significant_below_mde",
        "d6": "stands",
        "demonstrated_absence": True,
        "favours": favours,
        "reading": (
            "the withheld population's presence in training did not measurably "
            "change the arm's answer at this experiment's resolution. D6 stands "
            "as written. Failing to resolve a difference is not proof of none, "
            "but this is the one cell where the experiment saw what it was "
            "powered to see"
        ),
    }


def sensitivity_contrast(
    name: str,
    with_withheld: Mapping[str, bool],
    without_withheld: Mapping[str, bool],
    *,
    alpha: float,
    power: float,
) -> dict:
    """One pair's paired contrast, through `evaluate`'s own implementation.

    ``family`` is ``None`` and not a name: this is a diagnostic about the data,
    reported outside `evaluation.contrasts`, Holm-corrected with nothing. Giving
    it a family would spend the correction budget of the family that answers the
    gate's question.

    Raises:
        ValueError: If the two arms were not scored on the same groups. They
            share a fold manifest by construction, so a mismatch means the
            construction was violated upstream and the pairing is not what it
            claims.
    """
    return _CONTRAST_IMPLEMENTATION(
        {"name": name, "family": None, "arms": ["with_withheld", "without_withheld"]},
        with_withheld,
        without_withheld,
        alpha,
        power,
    )


def read_contrast(contrast: Mapping) -> dict:
    """Apply the rule to one contrast, returning it with its cell attached."""
    significant = contrast["p_value"] <= contrast["alpha"]
    return {
        **contrast,
        "reading": reading_cell(
            significant=significant,
            observed=contrast["observed_difference"],
            mde=contrast["minimum_detectable_effect"],
        ),
    }


def write_sensitivity_report(
    directory: Path | str,
    *,
    version: str,
    manifest_digest: str,
    contrasts: Sequence[Mapping],
    seeds: Mapping,
    runtimes: Mapping[str, Mapping | None],
) -> dict:
    """Write the verdict, whichever way it reads.

    Committed either way and with everything needed to reproduce it: an
    experiment that reported only when it found something would be one nobody
    could read a null from.

    Args:
        runtimes: What each arm's own folds recorded, **read back from the
            artifacts** and not taken from the reporting process. The two are the
            same only when one machine ran everything, and this experiment is
            explicitly allowed to span two — a GPU host for the incumbent and
            this one for the descriptors. A single stack copied from whoever
            wrote the report would describe half the run and claim to describe
            all of it. ``None`` for an arm whose folds predate the record.
    """
    read = [read_contrast(contrast) for contrast in contrasts]
    reopened = [
        entry["name"] for entry in read if entry["reading"]["d6"] == "re-opened"
    ]

    report = {
        "spec": "0057",
        "dataset_version": version,
        "manifest_digest": manifest_digest,
        "withheld_population": WITHHELD_POPULATION,
        "measured_arms": [*DESCRIPTOR_PAIR, *CNN_PAIR],
        "reading_rule": READING_RULE,
        "licence": LICENCE,
        "contrasts": read,
        "verdict": {
            # Either arm is enough: an arm that is affected is affected whatever
            # the other arm did, and requiring both would let one clean result
            # bury one dirty one.
            "d6": "re-opened" if reopened else "stands",
            "reopened_by": reopened,
        },
        "seeds": dict(seeds),
        "runtimes": {arm: dict(runtime) if runtime else None
                     for arm, runtime in runtimes.items()},
    }

    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / SENSITIVITY_REPORT_FILENAME).write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return report
