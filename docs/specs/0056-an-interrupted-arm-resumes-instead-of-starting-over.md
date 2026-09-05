# SPEC: feat(ml): resume an interrupted arm and refuse to overwrite a finished one

## Problem

`crossval.run_arm` walks every repeat and every outer fold unconditionally, and
each fold trainer writes into `fold_directory(arm_dir, repeat, fold)` with no
existence check. Two failures follow from the same missing branch.

**An interrupted run loses everything it computed.** The capture-population
probe (SPEC 0055) was killed at 17 of 25 folds; `load_arm_predictions` refuses a
partial arm by design, so no figure could be produced and all seventeen folds
were discarded. That is cheap at the descriptor arm's 147 s per fold. It is not
cheap at what is now queued: the D6 sensitivity comparison is about two hours,
and the E0 gate (SPEC 0044) is about twenty — `cnn` and `shuffled_control` at
roughly 930 s per fold over 25 folds each, `descriptors` at 147 s, the frozen
encoder unmeasured, plus the descriptor ablation. A twenty-hour run that cannot
survive one interruption is a run that may never finish on this machine, which
already killed one.

**Re-running an arm silently overwrites the artifacts a published result
names.** This is [#26](https://github.com/LukeSantossz/visiosoil-app/issues/26),
open and rescoped, and it matters more under k-fold than it did under a single
run: a result now spans k × R directories, so a partial re-run leaves an arm
whose folds came from two different trainings with nothing in the artifacts
saying so. There is no `--force` anywhere in `ml/`.

The two are the same `if` in the same loop. A change that added resume without
the refusal would make the second failure worse, because it would recompute a
stale fold quietly rather than loudly.

## Design Decision

**`run_arm` classifies each fold's directory before running it, and the three
outcomes are decided by what the artifacts can prove rather than by what the
operator remembers.**

| Directory | Outcome |
|---|---|
| Complete, and its provenance matches this run | **Reused.** Not touched, not recomputed, reported as reused. |
| Incomplete — killed part-way, or unreadable | **Recomputed.** It was never a result. |
| Complete, but its provenance differs | **The whole run is refused**, naming every such fold and the flag that would allow it. |

**Completeness is `cost.json` plus a parseable `predictions.json`.** `cost.json`
is written last, after the predictions, so its presence is the fold's commit
point. A `predictions.json` that does not parse is a process killed mid-write and
is treated as incomplete, not as a corrupt result to be pooled.

**Provenance is four things, all already written per fold except one.** The
fold's `config.json` must equal the run's resolved configuration; its
`predictions.json` header must carry the same `arm` and `shuffled_control`; and
it must carry the **manifest digest**, which is the one thing no fold records
today. `write_fold_predictions` gains it. Without it, two runs over the same
`dataset_version` whose manifest changed underneath — which `measure_scale.py`
does routinely — are indistinguishable, and resume would pool folds computed
from different data.

**The library versions are checked, and not here.** *Amended during
implementation, 2026-09-05.* This spec first put the recorded `runtime.json`
into the reuse predicate. It cannot go there: the runtime a fold would record
now is produced by `seed_everything`, which lives behind TensorFlow, and
`crossval.py` defers that import precisely so a run that is going to be refused
is refused before paying for it. Reading it early would make every refusal cost
half a minute, and building a second, cheaper version of the same record would
create two descriptions of one runtime that can disagree.

It becomes a **separate check after the loop and before anything is pooled**:
`require_uniform_runtime` refuses an arm whose folds did not all record the same
runtime, naming the folds that differ. That is stronger than the original
placement rather than weaker — it catches runtime drift in a run that resumed
nothing at all, which the reuse predicate by construction never could — and it
runs where the record it compares already exists on disk for every fold.

**A fold written before this spec carries no digest and is therefore not
reusable.** It falls into the third row and the run is refused unless forced.
Absent is not the same as matching, and this repository already refuses to
assume the safe value when a record is missing — `load_runtime` and
`load_fine_tune` return `None` for exactly this reason and say so.

**`--force` recomputes every fold and is recorded in the artifacts.** Off by
default. A forced fold's `predictions.json` header carries `"forced": true`, so a
re-run is visible in the result rather than only in a shell history. The refusal
message names `--force` explicitly, so an operator who means to discard a
published result says so in the command.

**The refusal names every stale fold, not the first.** An operator deciding
whether to force needs the whole cost of that decision in one message; a refusal
that reveals it one fold at a time turns one decision into twenty-five.

**A fold's completion marker is cleared before the fold is computed.** *Added
2026-09-05, from R3.* The classification above is only as good as the state a
half-finished recomputation leaves behind, and without this it is worthless in
exactly the case it exists for. A trainer overwrites `config.json` and
`runtime.json` before it writes any prediction; killed in between, the fold keeps
the **old** `predictions.json` and the **old** `cost.json` beside the **new**
`config.json` — and the next run reads it as complete, matching, reusable, and
pools predictions from one configuration under the record of another. Removing
the marker first makes that state `INCOMPLETE`, which is what it is. Nothing else
is removed: the predictions are what a recomputation overwrites anyway, and
deleting them here would destroy a result before its replacement exists.

**The per-fold entry point plans its one fold, through the same planner.**
*Added 2026-09-05, from R3.* `src.train.train` called the trainer directly, so a
re-run through it overwrote a finished fold silently **and recorded
`forced=False`** — an overwrite the artifacts denied having happened. This spec's
Scope did not name `train.py`, and it should have: that is the entry point CI
dispatches one job per fold to, which `train.py`'s own comment already says makes
it "the path a published result comes from". A contract that holds at `run_arm`
and not there protects the path nobody's published numbers came from. It asks
`plan_arm_run` with `only=(repeat, fold)` rather than carrying a second copy of
the rule, because two implementations of one refusal are how the two come to
disagree.

**The same classification runs in `scripts/run_population_probe.py`.** It is a
second 25-fold loop with the same failure — it is what the interruption actually
happened to — so the check lives in `crossval.py` and both callers use it. A
guard that protected only the arms would leave the probe exactly where it was.

**Nothing about a fold's training changes.** This spec adds a decision about
whether to run a fold, and one field to what a fold records. It does not touch
the recipe, the nesting, the selection or the pooling, so an arm resumed across
an interruption is byte-for-byte the arm that would have run without one — which
is the property that makes resume legitimate rather than merely convenient.

## Alternatives Considered

- **Refuse a non-empty arm directory outright, per #26's rescoped criteria, and
  add no resume.** Rejected. It fixes the overwrite and leaves the twenty-hour
  run unable to survive an interruption, which is the failure that has actually
  occurred. #26's criteria were written before the k-fold protocol made a run
  long enough for interruption to be the common case.
- **Resume on the presence of `predictions.json` alone.** Rejected, and it is
  the tempting shortcut. It cannot distinguish a fold from this configuration
  from one computed before the config changed, so it would silently pool folds
  from two different runs — the exact defect #26 describes, reintroduced by the
  fix for it.
- **Recompute a stale fold silently instead of refusing.** Rejected. It produces
  a uniformly current arm, which sounds correct, and destroys the artifacts of a
  published result to do it. The operator must be the one who decides that.
- **Checkpoint inside a fold so an interrupted fold resumes mid-training.**
  Rejected as disproportionate. The unit that costs is the fold, not the epoch:
  at 25 folds an interruption loses at most one fold's work once resume exists,
  which is 15 minutes on the most expensive arm. Mid-fold checkpointing would
  add a second selection surface to a protocol whose whole point is that
  selection is audited.
- **Write a lock file and treat its absence as completion.** Rejected. It adds a
  state that can disagree with the artifacts, and a killed process leaves it
  behind. `cost.json` already is the commit point and cannot be stale in a way
  the artifacts do not show.
- **Compare provenance by hashing the fold directory.** Rejected. It would make
  any change to an unrelated artifact — a `model.keras` re-serialised by a new
  Keras build — read as a configuration change, so it would refuse runs that are
  in fact resumable while proving nothing extra.

## Scope

- Includes:
  - `ml/src/crossval.py` — `fold_reuse_state` (new) classifying one fold
    directory and `require_uniform_runtime` (new) refusing an arm whose folds
    ran under different library versions; `write_fold_predictions` records the
    manifest digest and whether the fold was forced; `run_arm` gains `--force`,
    partitions the folds before running any, refuses on stale folds naming all
    of them, and reports what it reused.
  - `ml/scripts/run_population_probe.py` — the same classification in its loop,
    and the same `--force`.
  - `ml/src/train.py` — `begin_fold` before the trainer, and the per-fold entry
    point plans its one fold through `plan_arm_run(only=...)` and gains
    `--force`. **Added to this Scope on 2026-09-05**, from R3: leaving it out
    would have left the contract false at the entry point CI actually uses.
  - `ml/tests/` — one test per acceptance criterion below.
- Does NOT include:
  - Any change to a fold's training recipe, the nested selection, the pooling,
    or `evaluate.py`.
  - Mid-fold checkpointing.
  - Running any arm, the D6 sensitivity comparison, or the E0 gate.
  - The `texture_class` spanning-group guard, which is
    [#229](https://github.com/LukeSantossz/visiosoil-app/issues/229).
  - Any change under `lib/`.

## Acceptance Criteria

- a_complete_fold_of_this_run_is_not_recomputed: a second `run_arm` over an arm
  whose folds are complete and match runs no training and leaves every
  artifact's modification time unchanged.
- an_incomplete_fold_is_recomputed: a fold directory holding `predictions.json`
  but no `cost.json` is recomputed, and so is one whose `predictions.json` does
  not parse.
- a_fold_from_another_configuration_refuses_the_run: a fold whose `config.json`
  differs from the run's stops the run before any training, and nothing is
  written.
- a_fold_from_another_manifest_refuses_the_run: a fold whose recorded manifest
  digest differs stops the run, even when the dataset version and the
  configuration are identical.
- a_fold_predating_this_record_is_not_reusable: a fold with no recorded manifest
  digest is treated as unproven rather than as matching, and refuses the run.
- the_refusal_names_every_stale_fold: the message lists every fold directory
  that would be overwritten, not only the first, and names `--force`.
- force_recomputes_and_is_recorded: `--force` runs every fold, and each fold's
  `predictions.json` header carries that it was forced.
- a_control_and_its_arm_do_not_reuse_each_other: a fold recorded with
  `shuffled_control` true is not reusable by a run without the flag, and the
  reverse.
- an_arm_whose_folds_ran_under_different_libraries_is_refused: an arm holding two
  folds with different recorded `runtime.json` values is refused before anything
  is pooled, naming the folds that differ — whether or not the run resumed.
- the_probe_resumes_on_the_same_rule: `run_population_probe.py` reuses,
  recomputes and refuses by the same classification, asserted against the same
  function.
- no_fold_begins_while_still_marked_finished: a trainer is never entered on a
  fold whose `cost.json` is still there, so an interrupted recomputation leaves
  the fold incomplete rather than falsely complete.
- the_per_fold_entry_point_refuses_a_stale_fold: `src.train.train` reuses a
  matching fold, refuses a stale one naming `--force`, and records `forced` when
  it is given — the same three outcomes `run_arm` has.
- a_resumed_arm_equals_an_uninterrupted_one: an arm run in two halves across a
  simulated interruption produces the same pooled predictions as the same arm run
  in one pass.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/ -q
```

The behaviour is decided by files on disk and needs no dataset; every test above
builds its fold directories from fixtures. Python 3.12.13 and the pinned stack of
`ml/requirements.txt`, unchanged; no dependency is added.

Against the real archive the change is observable without training anything, on
a directory this spec produced: a completed `models/v1/population_probe` re-run
reports twenty-five folds reused and exits in seconds where it previously spent
twenty-eight minutes.

**The directories already on this machine are not that.** Every fold under
`models/v1/` was written before folds recorded a manifest digest, so each is
unproven by the rule above and the first run after this change refuses, naming
all twenty-five and `--force`. That is the intended behaviour and its cost is
one forced run per existing arm — a `population_probe` directory whose verdict
is already committed, and a `cnn` directory holding a single fold that no
reported number depends on.

## Risks and Assumptions

- **Assumption: `cost.json` is written after `predictions.json` in every arm.**
  It is, in `train.py` and in `arms/probe.py`, and the artifact timestamps of the
  probe's run show it. A future arm that wrote them in the other order would make
  an incomplete fold look complete; the criterion above pins the order by
  behaviour rather than by convention.
- **Assumption: the resolved configuration is comparable by equality.** It is a
  plain mapping loaded from YAML with paths resolved, and it is already written
  per fold and read back by `read_fold_metadata`'s neighbours. Absolute paths are
  in it, so moving the checkout invalidates reuse — correctly, since a fold's
  images would then have come from elsewhere.
- **Risk: resume hides a real change.** If a change alters training without
  altering the configuration, the arm name or the manifest — and without moving
  a library version, which `require_uniform_runtime` would catch afterwards —
  a resumed run mixes old and new code. That is the residual gap, it is named
  here rather than left implicit, and `--force` is what closes it for an operator
  who knows the code moved. Recording a source digest per fold was considered and
  is a larger change than this one.
- **Risk: an operator forces out of habit and destroys a published result.** The
  refusal names every fold and the flag, so the cost is stated once and in full;
  beyond that this is a decision the operator is entitled to take.
- **What would invalidate this spec:** a change to the per-fold artifact layout,
  to `load_arm_predictions`'s refusal of a partial arm, or to the evaluation
  protocol's fold identity.
