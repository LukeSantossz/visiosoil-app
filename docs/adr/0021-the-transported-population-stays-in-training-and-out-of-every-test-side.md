# ADR 0021: The transported population stays in training and out of every test side

## Decision

**SPEC 0040 D6 stands unchanged.** Capture population `B` — the 20 sample groups
delivered as transported copies — **may train, and may never be validated or
tested on.** Nothing in the pipeline, the configuration or the arms changes.

Taken 2026-09-11 by the Developer, against the numbers in
[SPEC 0057's verdict](../ml/transported-population-sensitivity.md).

## Why this record exists at all

[SPEC 0055](../specs/0055-probe-whether-the-capture-population-is-predictable.md)
pre-registered a rule: if the capture population turned out to be recoverable
from the same patches the texture arms see, D6 would be **re-opened by name**,
and the choice would lie between two branches fixed in advance so that neither
could be invented after the numbers arrived. The probe recovered 90 of 97 sample
groups, Wilson lower bound 0.858 against a prior of 0.649, so D6 was re-opened.

[SPEC 0057](../specs/0057-measure-whether-the-transported-population-changes-the-answer.md)
then measured the thing that actually matters, which is not whether the
information is *present* but whether the arms *use* it. Its verdict:

> Both contrasts landed in `not_significant_below_mde`. SPEC 0040 D6 stands, and
> neither arm re-opened it.

| Contrast | McNemar p | Observed difference | Minimum detectable effect |
|---|---|---|---|
| `descriptors_sensitivity` | 0.7539 | −0.0260 | 0.1082 |
| `cnn_sensitivity` | 0.2005 | **+0.1039** | 0.1941 |

## Why "unchanged" is one of the answers

`ml-implementation-map.md` described this record as choosing between the two
branches SPEC 0055 fixed — `B` leaves training entirely, or `B` is restricted to
arms that provably cannot exploit an encoding signature. Taking neither can read
like a third option invented to avoid the work, so the reason it is not is worth
stating plainly.

Those two branches are what to do **if the effect is real**. The reading rule
that fixed them is the same rule that returns "nothing changes" when neither
contrast fires. Both are below their own measurement floor; one of them points
the wrong way for removal. Writing that down is the decision. Changing the
pipeline on a null would be the deviation.

## The asymmetry the decision rests on

`B` is **already excluded from every test side**, and that is the half of D6
nobody proposed changing.

So a compression artefact learned from `B` cannot inflate a score. Test sides are
populations `A` and `C`; a `B`-specific shortcut is worthless there and costs
accuracy rather than flattering it. The failure D6 was written against — a
transported copy sitting in the test set, letting a model read artefacts instead
of texture — is closed by the part of the rule that is not in question.

What remained was narrower: that `B`'s presence might *contaminate what the model
learns*. That is what SPEC 0057 measured, and it did not find it. The incumbent
arm's point estimate is **+10.4 points in favour of keeping `B` in training** —
not a result, because it sits below its own floor of 19.4, but not evidence for
removal either.

## What removal would have cost

Counted over dataset version `v1`, in sample groups, for the four classes the
model emits:

| Class | With `B` | `B` | Without `B` | Loss |
|---|---:|---:|---:|---:|
| Arenosa | 26 | 6 | 20 | 23 % |
| Media | 22 | 2 | 20 | 9 % |
| Muito Argilosa | 21 | 0 | 21 | 0 % |
| **Argilosa** | **33** | **17** | **16** | **52 %** |
| Total | 102 | 25 | 77 | 25 % |

In training photographs Argilosa falls from 63 to 30 — the same 52 %.

**The cost does not spread across the dataset. It lands on one class.** And on
the one class [ADR 0016](0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)'s
amendment records as the only one still clearing its floor of 30 samples, the
floor that removed Siltosa from the first model. Removal would make Argilosa the
*smallest* of the four and leave no class above that floor at all.

That does not reopen ADR 0016's floor, which its own amendment already leaves
open. It does mean the rejected branch would have paid a certain, concentrated
price for an uncertain, unmeasurable gain.

**The partition does not move either way.** `B` is train-only, so it was never in
the splittable pool: 77 groups before and after. Every published number drawn
over those folds stands whichever branch is taken, which is why this decision
could wait for a measurement instead of blocking on one.

## Options rejected

- **`B` leaves training entirely.** The branch this record was expected to take,
  and the one initially chosen before the per-class arithmetic above existed.
  Rejected on that arithmetic: it pays 52 % of Argilosa's evidence for an effect
  the only experiment able to see it did not see, whose point estimate points the
  other way, and whose principal risk is already closed by `B`'s exclusion from
  every test side. Its one real merit is kept rather than dismissed — a null at
  this resolution is not proof of absence — and it is why this record is
  revisitable.
- **Restrict `B` to arms that provably cannot exploit an encoding signature.**
  Rejected because the proof has nothing to stand on. SPEC 0057 explicitly cannot
  separate "an encoding signature helping" from "37 more photographs helping", so
  eligibility would be asserted rather than demonstrated, and re-argued for every
  arm added later.
- **Defer the decision until after the E0 gate runs.** Rejected: SPEC 0044 waits
  on this record by name, and running twenty hours of arms under a rule nobody
  has written is the failure pre-registration exists to prevent.

## Consequences

- **The E0 gate is unblocked.** SPEC 0044 (#216) runs the incumbent arms —
  `descriptors`, `cnn`, `encoder_probe`, `shuffled_control` — with no change to
  any of them.
- **`descriptors_without_b` and `cnn_without_b` stay** as the diagnostic they
  were built as, and their published results stay published. They are not the
  canonical arms and were never meant to be.
- **This is taken on the best measurement that will ever exist here, which is not
  the same as a strong one.** The descriptor contrast resolved to 10.8 points and
  the incumbent only to 19.4; ADR 0016 closed the dataset at 105 samples, so no
  larger `N` is coming.

## What would reopen this

- A new arm whose representation is unlike both measured ones, where the
  eligibility question has to be asked again rather than inherited.
- Any evidence that a **test-side** score moves with capture population, which
  would falsify the asymmetry the decision rests on.
- A dataset version that admits new material, which would change both the
  arithmetic and the resolution.
