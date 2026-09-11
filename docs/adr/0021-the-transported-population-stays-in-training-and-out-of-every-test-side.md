# ADR 0021: The transported population stays in training and out of every test side

## Status

Accepted 2026-09-11, promoted from
[SPEC 0062](../specs/0062-settle-d6-and-unblock-the-e0-gate.md) at the Spec Gate.

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

**The authorisation comes from SPEC 0057, not from SPEC 0055, and the difference
matters enough to state.** SPEC 0055's rule is keyed to the probe's Wilson bound
and says *"the two options are stated now so the choice is not invented after the
number … **which one** is an ADR written against the number"*. Its trigger fired,
its enumeration is "which one", and it contains no contrast — SPEC 0057 did not
exist when it was written. Read alone, it does not license "neither".

What licenses "neither" is
[SPEC 0057](../specs/0057-measure-whether-the-transported-population-changes-the-answer.md),
whose reading rule is an exhaustive four-cell table fixed before its run, and in
which **three of the four cells read "D6 stands"**. Both contrasts landed in the
fourth — not significant, below the minimum detectable effect — which that spec
and its verdict both call the clean null. So "unchanged" is pre-registered, by
the experiment that was built to decide it.

An earlier draft of this record claimed SPEC 0055's rule "is the same rule that
returns nothing changes". That was a convenient re-reading of a document that
does not say it, and it is corrected here rather than left standing, because a
decision resting on a misquoted pre-registration is the failure pre-registration
exists to prevent.

## The asymmetry the decision rests on

`B` is **excluded from every test side of `v1`'s partition**, and that is the
half of D6 nobody proposed changing. Verified by execution over the committed
`ml/data/splits/splits.json` rather than read off the rule: across all 5 repeats
by 5 outer folds, and all 4 inner folds of each, **no population-`B` photograph
appears on any outer test side or any inner validation side**, and exactly 77
distinct groups are ever tested.

Stated about the data rather than about the code, deliberately.
`train_only_sample_ids` marks a sample train-only only when *every* photograph of
it is `B`, so a sample mixing an `A` photograph with `B` ones would be splittable
by design. `v1` contains no such sample — nor any `sample_id` spanning two
classes — which is why the claim holds here. A dataset version that admitted
mixed samples would need it re-checked, and that is listed below as a reopener.

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

Counted in sample groups over **the partition, not the raw manifest**, for the
four classes the model emits. Which basis is used matters by up to four
percentage points and by one whole class, so it is named rather than assumed:
the patch grid refuses 11 photographs of `v1` as too coarse to normalise, **all
11 of them population `B`**, and those refusals remove 5 entire `B` groups before
any fold is drawn. What the pipeline holds is 97 groups, not the manifest's 102.

| Class | With `B` | `B` | Without `B` | Loss |
|---|---:|---:|---:|---:|
| Arenosa | 25 | 5 | 20 | 20 % |
| Media | 20 | 0 | 20 | 0 % |
| Muito Argilosa | 21 | 0 | 21 | 0 % |
| **Argilosa** | **31** | **15** | **16** | **48 %** |
| Total | 97 | 20 | 77 | 21 % |

In training photographs Argilosa falls from 57 to 30, a 47 % cut; `B` holds 37 of
the partition's 204, which is the 18 % of the training pool SPEC 0057's verdict
names.

**Media pays nothing.** Both of its `B` groups are among the five the patch grid
already refuses, so they reach no training side today. An earlier draft of this
table counted the raw manifest and billed Media 9 % and Argilosa 52 %; the
figures above are what the pipeline actually holds, and they are what the
decision is taken on.

The raw-manifest basis is not wrong, only different, and one record uses it:
[ADR 0016](0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)'s
amendment says Argilosa "clears it at 33", which is the manifest count. Against
the floor of 30 the conclusion is the same on either basis — 33 and 31 both clear
it, 16 does not.

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
  Rejected on that arithmetic: it pays 48 % of Argilosa's evidence for an effect
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
- **Defer the decision until after the E0 gate runs.** Rejected: running twenty
  hours of arms under a rule nobody has written is the failure pre-registration
  exists to prevent. The dependency is real but it lives in
  `ml-implementation-map.md` and `ml-handoff.md`, not in SPEC 0044 — that spec
  names neither this record, nor D6, nor SPEC 0057, and an earlier draft of this
  bullet claimed it "waits on this record by name", which is false.

## Consequences

- **The E0 gate is unblocked.** SPEC 0044 (#216) runs the incumbent arms —
  `descriptors`, `cnn`, `encoder_probe`, `shuffled_control` — with no change to
  any of them.
- **`encoder_probe` runs uncleared, and that is carried here rather than left in
  the verdict.** SPEC 0057's licence is explicit: it measured `descriptors`,
  `descriptors_without_b`, `cnn` and `cnn_without_b`, and it **does not clear
  `encoder_probe`**. That spec made the licence an acceptance criterion and
  called it the most likely way for a correct number to be misused, so a
  decision record that unblocks a twenty-hour run must not be the place the
  caveat goes missing. Nothing measured says `B` is safe in that arm's training
  side; what the gate has is a rule that applies to it by inheritance, and a
  contrast that never tested it.
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
  arithmetic and the resolution — or one holding a sample whose photographs span
  two capture populations, which `train_only_sample_ids` would leave splittable
  and which would put `B` photographs on a test side. `v1` holds none; nothing in
  `create_folds_for_config` refuses one.
- `encoder_probe` producing a result the gate acts on, since no measurement
  covers `B`'s effect on that arm.
