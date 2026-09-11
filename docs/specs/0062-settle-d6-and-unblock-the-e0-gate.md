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

**Corrected during implementation, by the adversarial review that stood in for
R2.** This section first claimed SPEC 0055's own rule returns "unchanged" when
neither contrast fires. It does not: that rule is keyed to the probe's Wilson
bound, its enumeration is "which one", and it predates SPEC 0057 entirely. The
claim was a convenient re-reading of the one document that does not license the
conclusion.

What does license it is **SPEC 0057**, whose reading rule is an exhaustive
four-cell table fixed before the run, in which **three of the four cells read "D6
stands"**. The probe demonstrated the capture population is *recoverable*, which
re-opened D6 by name; SPEC 0057 then measured whether the texture arms *exploit*
it, and [its verdict](../ml/transported-population-sensitivity.md) is explicit:
**"Both contrasts landed in `not_significant_below_mde`. SPEC 0040 D6 stands, and
neither arm re-opened it."** Writing that down is what this spec is for; inventing
a change the measurement did not ask for would be the deviation.

### The asymmetry that decides it, and which no record had stated

`B` is **excluded from every test side of `v1`'s partition** — verified by
execution over the committed fold manifest, not read off the rule: no `B`
photograph reaches any outer test side or inner validation side across all 25
outer folds and their inner folds. A compression artefact the model learns from
`B` therefore cannot inflate the score: the test sides are
populations `A` and `C`, and a `B`-specific shortcut is useless there — it costs
accuracy rather than flattering it. The risk D6 was written against, a
transported copy in the test set letting a model read artefacts instead of
texture, is closed by the half of D6 that is not in question.

What remains is the narrower hypothesis that `B`'s presence *contaminates what
the model learns*. That is the hypothesis SPEC 0057 measured, and it did not
find it — with the incumbent's point estimate at **+10.4 points favouring
`B`-in-training**, below its own floor of 19.4 and therefore not a result, but
pointing away from removal rather than towards it.

### What removal would have cost, counted from the partition

Measured over the **partition** of `v1` — not the raw manifest — for the four
classes the model emits, in sample groups:

| Class | With `B` | `B` | Without `B` | Loss |
|---|---:|---:|---:|---:|
| Arenosa | 25 | 5 | 20 | 20 % |
| Media | 20 | 0 | 20 | 0 % |
| Muito Argilosa | 21 | 0 | 21 | 0 % |
| **Argilosa** | **31** | **15** | **16** | **48 %** |
| Total | 97 | 20 | 77 | 21 % |

**Corrected during implementation.** The first version of this table counted the
raw `manifest.csv` and gave 102 / 25 / 25 %, with Argilosa at 52 % and Media at
9 %. That is the wrong basis: the patch grid refuses 11 photographs of `v1`,
**all 11 of them population `B`**, and those refusals remove 5 entire `B` groups
before any fold is drawn. Media's two `B` groups are among them, so **Media pays
nothing at all**. Every downstream record — SPEC 0055, SPEC 0057 and the verdict
— uses the partition basis and its 20 groups; only ADR 0016's amendment uses the
manifest basis, and the ADR names both so the two reconcile.

In training photographs Argilosa falls from 57 to 30, a 47 % cut. **The cost is
not spread across the dataset; it lands almost entirely on one class**, and on
the one class ADR 0016's amendment records as the only one still clearing its
floor of 30 samples. Removal would make Argilosa the *smallest* class of the four
and leave no class above that floor.

The splittable pool is 77 groups either way — `B` is train-only, so it was never
in the partition — which is why the folds, the digest and every published number
drawn over them are untouched by this decision in both directions.

## Alternatives Considered

- **`B` leaves training entirely.** The option this record was expected to take,
  and the one the Developer initially chose before the per-class arithmetic
  above was computed. Rejected on that arithmetic: it pays 48 % of Argilosa's
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
- **Defer ADR 0021 until after the gate runs.** Rejected: running twenty hours
  of arms under a rule nobody has written is exactly the failure pre-registration
  exists to prevent. The dependency is real but it lives in the architecture
  documents, not in SPEC 0044 — which names neither this record, nor D6, nor
  SPEC 0057. An earlier version of this bullet said SPEC 0044 "waits on it by
  name"; it does not.
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
  - **Added during implementation, and named here rather than done in silence:**
    three docstrings that speak of ADR 0021 in the future tense —
    `ml/src/arms/withheld.py`, `ml/scripts/run_d6_sensitivity.py` — and the
    `Last updated` headers of both architecture documents. The Scope below
    excludes `ml/src/` because a *behaviour* change would contradict the
    decision; a docstring that says the decision is still to come is the same
    stale pointer this spec exists to fix, in a file that happens to be code.
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
- `no_record_still_waits_on_adr_0021` — no file under `docs/` describes the D6
  decision as pending, undecided, awaiting the Developer, or blocking the gate.
  **`docs/specs/` and `docs/ml/` are the two exceptions**, named in the guard and
  asserted to exist: an approved spec keeps the text it was approved with and a
  run verdict records what was measured, so editing either to match a later
  decision is what `spec_method.md` forbids. Everything else under `docs/` is
  scanned, and the decision is matched under every name the records give it —
  the first version of this guard looked only for the literal "ADR 0021" and
  missed the handoff's own "the gate still waits … the arms D6 settles on".
- `the_records_agree_on_what_blocks_the_gate` — neither the handoff nor the
  implementation map names ADR 0021 as a blocker of SPEC 0044 any more.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe -m pytest tests/test_records.py -q
flutter test test/standards/
mf check
```

The per-class counts in the Design Decision are read from the **fold manifest**,
`ml/data/splits/splits.json`, drawn over `ml/data/datasets/v1/manifest.csv` at
digest `49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9`. Each
group in `groups` is counted once, `train_only` marks it as population `B`, and
`class` gives its class.

Reading the fold manifest rather than the CSV is the whole point of the
correction recorded above: the CSV holds 102 groups and the partition holds 97,
because the patch grid refuses 11 photographs — all of them `B` — and with them
5 entire `B` groups. `splits.json` is tracked since SPEC 0061, so the counts
reproduce from a checkout alone; only the training-photograph figures need the
ingested archive, and those are evidence in the pull request rather than an
acceptance criterion.

## Risks and Assumptions

- Assumption: **SPEC 0057's** pre-registered reading rule is what governs D6
  once SPEC 0055 re-opened it, and that rule permits "unchanged" — three of its
  four cells read "D6 stands". An earlier version of this bullet said SPEC 0055's
  rule permits it, which contradicts the Design Decision above and is not what
  SPEC 0055 says. What would invalidate the assumption: a reading under which the
  probe's positive result alone obliges a change regardless of the sensitivity
  comparison — in which case SPEC 0057 was an experiment whose outcome could not
  matter, which is not how it was written.
- Assumption: `B` being absent from every test side is what closes the inflation
  risk. It is asserted rather than assumed —
  `test_create_folds_places_no_group_b_sample_in_a_test_side` guards it, the
  sensitivity run asserted it again over its own arms, and it was re-verified by
  enumerating every fold of the committed partition. It is a property of `v1`'s
  data and not of the rule: `train_only_sample_ids` marks a sample train-only
  only when every photograph of it is `B`, so a mixed sample would be splittable
  by design. `v1` holds none, and nothing refuses one.
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
