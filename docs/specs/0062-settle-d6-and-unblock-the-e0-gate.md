# SPEC: docs(ml): settle D6 against the sensitivity numbers and unblock the E0 gate

## Problem

Four records name ADR 0021 as the decision the E0 feasibility gate waits on, the
sensitivity comparison that was to decide it has run and published its verdict,
and the decision record does not exist — so the gate is blocked by a document
nobody has written rather than by anything unresolved.

## Design Decision

**SPEC 0040 D6 stands unchanged: capture population `B` may train and may never
be validated or tested on.** ADR 0021 is promoted from this decision at the Spec
Gate and records it, against SPEC 0057's numbers, with the arithmetic of what
changing it would have cost. No pipeline code, no configuration and no arm
changes.

### Why "no change" is an answer and not an evasion

`ml-implementation-map.md:160` says ADR 0021 "chooses between the two options
SPEC 0055 fixed in advance — `B` leaves training entirely, or `B` is restricted
to arms that provably cannot exploit an encoding signature". Taking neither looks
like a third option invented after the fact, so the reason it is not is stated
here rather than left for a reader to reconstruct.

Those two options are what SPEC 0055 pre-registered **as the branches to take if
the effect were real**. The probe demonstrated the capture population is
*recoverable*, which re-opened D6 by name; SPEC 0057 then measured whether the
texture arms *exploit* it, and
[its verdict](../ml/transported-population-sensitivity.md) is explicit:
**"Both contrasts landed in `not_significant_below_mde`. SPEC 0040 D6 stands, and
neither arm re-opened it."** The reading rule that fixed the two options is the
same rule that returns "unchanged" when neither fires. Writing the decision down
is what this spec is for; inventing a change the measurement did not ask for
would be the deviation.

### The asymmetry that decides it, and which no record had stated

`B` is **already excluded from every test side**. A compression artefact the
model learns from `B` therefore cannot inflate the score: the test sides are
populations `A` and `C`, and a `B`-specific shortcut is useless there — it costs
accuracy rather than flattering it. The risk D6 was written against, a
transported copy in the test set letting a model read artefacts instead of
texture, is closed by the half of D6 that is not in question.

What remains is the narrower hypothesis that `B`'s presence *contaminates what
the model learns*. That is the hypothesis SPEC 0057 measured, and it did not
find it — with the incumbent's point estimate at **+10.4 points favouring
`B`-in-training**, below its own floor of 19.4 and therefore not a result, but
pointing away from removal rather than towards it.

### What removal would have cost, counted from the manifest

Measured over `v1` for the four classes the model emits, sample groups:

| Class | With `B` | `B` | Without `B` | Loss |
|---|---:|---:|---:|---:|
| Arenosa | 26 | 6 | 20 | 23 % |
| Media | 22 | 2 | 20 | 9 % |
| Muito Argilosa | 21 | 0 | 21 | 0 % |
| **Argilosa** | **33** | **17** | **16** | **52 %** |
| Total | 102 | 25 | 77 | 25 % |

In training photographs Argilosa falls from 63 to 30, the same 52 %. **The cost
is not spread across the dataset; it lands almost entirely on one class**, and
on the one class ADR 0016's amendment records as the only one still clearing its
floor of 30 samples. Removal would make Argilosa the *smallest* class of the
four and leave no class above that floor.

The splittable pool is 77 groups either way — `B` is train-only, so it was never
in the partition — which is why the folds, the digest and every published number
drawn over them are untouched by this decision in both directions.

## Alternatives Considered

- **`B` leaves training entirely.** The option this record was expected to take,
  and the one the Developer initially chose before the per-class arithmetic
  above was computed. Rejected on that arithmetic: it pays 52 % of Argilosa's
  evidence for an effect the only experiment able to see it did not see, whose
  point estimate points the other way, and whose main risk is already closed by
  `B`'s exclusion from every test side. Its one genuine merit — that a null at
  this resolution is not proof of absence — is recorded in ADR 0021 rather than
  dismissed, because it is the reason this decision is revisitable.
- **Restrict `B` to arms that provably cannot exploit an encoding signature.**
  Rejected because the proof has no basis to stand on. SPEC 0057 explicitly
  cannot separate "an encoding signature helping" from "37 more photographs
  helping", so an eligibility criterion would be asserted rather than
  demonstrated, and it would have to be re-argued for every arm added later.
- **Defer ADR 0021 until after the gate runs.** Rejected: SPEC 0044 waits on it
  by name, and running twenty hours of arms under a rule nobody has written is
  exactly the failure the pre-registration exists to prevent.
- **Amend SPEC 0040 D6 in place instead of writing an ADR.** Rejected: an
  approved spec is durable and is not edited to match a later decision, and the
  three tests for promotion all hold — the decision is hard to reverse once the
  gate has run under it, surprising without the sensitivity numbers, and a real
  alternative was rejected for a stated reason.
- **Record the decision only in the handoff and the map.** Rejected: those are
  pointers that are rewritten as work moves, and `mf check records` plus the
  README Engineering Decisions index exist so a decision has one durable home.

## Scope

- Includes:
  - `docs/adr/0021-*.md` (new) — the decision, its two rejected options, the
    per-class arithmetic, the already-excluded-from-test asymmetry, and what
    would reopen it.
  - `README.md` — the Engineering Decisions row for ADR 0021, which
    `test/standards/readme_adr_index_test.dart` requires of every ADR.
  - `docs/architecture/ml-handoff.md` — "Order of work" item 2 becomes taken,
    and the gate's stated blocker is lifted.
  - `docs/architecture/ml-implementation-map.md` — the ADR 0021 rows in §2 and
    §6, which currently describe a pending choice between two options.
  - `ml/tests/test_records.py` (new) — the criteria below.
- Does NOT include:
  - Any change to `ml/config.yaml`, to `ml/src/`, or to any arm. The decision is
    that nothing changes; a code change would contradict it.
  - Removing the `descriptors_without_b` and `cnn_without_b` arms. They stay as
    the diagnostic they were built as, and their results stay published.
  - Running the E0 gate. That is SPEC 0044 and issue #216, which this unblocks
    and does not perform.
  - Editing SPEC 0040, SPEC 0055 or SPEC 0057. All three are durable and all
    three are correct as approved; ADR 0021 is what they pointed forward to.
  - Editing `docs/ml/transported-population-sensitivity.md`. It is a run verdict
    and records what was measured.
  - Re-opening ADR 0016's floor of 30. This decision leaves that question
    exactly where ADR 0016's amendment left it, open, and says so.

## Acceptance Criteria

- `adr_0021_exists_and_states_the_decision` — `docs/adr/` holds a record
  numbered 0021 whose body states that SPEC 0040 D6 stands unchanged.
- `adr_0021_names_both_rejected_options` — it names both options SPEC 0055
  pre-registered, each with the reason it was not taken, so a reader cannot mistake
  "unchanged" for "unconsidered".
- `adr_0021_records_the_per_class_cost` — it carries the sample-group count the
  rejected option would have cost Argilosa, which is the number the decision
  turns on.
- `readme_indexes_adr_0021` — the README Engineering Decisions section links it;
  enforced by the existing `readme_adr_index_test.dart` guard.
- `no_record_still_waits_on_adr_0021` — no file under `docs/` describes ADR 0021
  as pending, undecided, or awaiting the Developer.
- `the_records_agree_on_what_blocks_the_gate` — neither the handoff nor the
  implementation map names ADR 0021 as a blocker of SPEC 0044 any more.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe -m pytest tests/test_records.py -q
flutter test test/standards/
mf check
```

The per-class counts in the Design Decision are read from
`ml/data/datasets/v1/manifest.csv` at digest
`49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9`, grouping on
`sample_id` within `texture_class` and counting distinct groups per
`source_group`. They need the ingested archive, so they are evidence in the pull
request and not an acceptance criterion — the criteria above are assertions about
the records, which run everywhere.

## Risks and Assumptions

- Assumption: the reading rule SPEC 0055 pre-registered permits "unchanged" when
  neither contrast fires. What would invalidate it: a reading under which the
  probe's positive result alone obliges a change regardless of the sensitivity
  comparison — in which case SPEC 0057 was an experiment whose outcome could not
  matter, which is not how it was written.
- Assumption: `B` being absent from every test side is what closes the inflation
  risk. It is asserted by the run rather than assumed —
  `test_create_folds_places_no_group_b_sample_in_a_test_side` guards it, and the
  sensitivity run asserted it again over its own arms.
- Risk, accepted and named in the ADR: **a null at this resolution is not proof
  of absence.** The descriptor contrast resolved to 10.8 points and the
  incumbent only to 19.4, and ADR 0016 closed the dataset at 105 samples, so no
  larger `N` is coming. This decision is taken on the best measurement that will
  ever exist here, which is not the same as a strong one.
- Risk: a later arm could exploit an encoding signature in a way neither measured
  arm did. What reopens this record is named in it — a new arm whose
  representation is unlike both measured ones, or any evidence that a test-side
  score moves with capture population.
- What would invalidate this spec: the discovery that `B` reaches a test side
  somewhere, which would make the asymmetry the decision rests on false.
