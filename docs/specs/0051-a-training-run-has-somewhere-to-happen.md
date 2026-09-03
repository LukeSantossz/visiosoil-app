# SPEC: build(ml): give a training run somewhere to happen, and name which environment a result came from

## Problem

Nothing in the ML programme can produce a number, because no environment can run a fit: the pinned stack has no wheel for the interpreter the repository is developed on, and no CI job runs a training (#214, roadmap item B1).

## Design Decision

Two environments, and the record says which one a published result must come from.

**The canonical environment is CI, one job per fold**, dispatched on demand. That is the Developer's decision of 2026-09-02 and it follows from the measurement: an arm is 25 folds and does not fit one GitHub-hosted job's six-hour ceiling, while a single fold does, comfortably. A matrix over `repeat` and `fold` gives 25 jobs that each name the same runner image and the same `ml/requirements.txt`, so two results are comparable because they were produced in the same declared environment rather than because two people's laptops happened to agree.

**A local Python 3.12 environment is supported and documented**, because iteration needs one and because the test suite is worth running whole. `ml/README.md` names the interpreter version rather than saying `python`, which is what it said while the stack had no wheel for the `python` most contributors have. **`ml/tests/test_requirements.py` passing rather than skipping is the check** that an environment is the pinned one — it already existed and already announced divergence; what was missing was an environment in which it could pass.

**A local result is not a published result.** The two environments produce the same numbers — the run is seeded, `enable_op_determinism` is on, and the fold manifest records the library versions it was drawn under — but only one of them is nameable by someone who did not run it. The record says so rather than leaving it to be assumed, and the fold's `runtime.json` already carries the library versions that let a reader check.

**The fold manifest is regenerated under the pinned stack.** It had been drawn under `scikit-learn 1.8.0` and `numpy 2.4.3`, which are outside `requirements.txt`'s ranges, and `load_folds` warned on every read that regenerating under the pinned versions would produce a different partition. `StratifiedGroupKFold` partitions differently across scikit-learn versions, so a fold manifest drawn outside the pins is one CI could never reproduce. It is git-ignored, so this is an operational step and not a committed change; the step is recorded here because skipping it silently produces incomparable results.

## Alternatives Considered

- **Local only.** Rejected by the Developer. It works and it is what iteration will use, but a result from it is named by a laptop, and #214's own argument is that one nameable environment is what makes two results comparable at all.
- **One CI job per arm rather than per fold.** Rejected on the measurement: 25 folds in one job exceeds the six-hour ceiling on GitHub-hosted runners, so the job would be killed part-way and leave an arm whose folds came from two different runs — the exact state the overwrite guard (#26) exists to prevent, arrived at by a different route.
- **A self-hosted runner.** Rejected for now. It removes the ceiling and the minutes cost, and it reintroduces the problem this spec is solving: an environment only one person can reproduce. Worth revisiting if Actions minutes become the binding constraint.
- **Run the arms on a rented GPU.** Rejected as premature. The gate that decides whether this programme continues has not run; buying hardware to accelerate a measurement that may end it is the wrong order, and CPU determinism is one fewer variable while E0 is the thing being measured.
- **Commit the fold artifacts so results travel with the repository.** Rejected. ADR 0019 makes a dataset version a build product and `ml/models/` is git-ignored by the same reasoning; the artifacts are uploaded per job and are downloadable from the run that produced them, which is where their provenance already points.
- **Skip the local environment and use CI for everything.** Rejected. A test suite that can only be run by pushing is a suite nobody runs before pushing, and 434 tests pass locally in under five minutes.

## Scope

- Includes:
  - `.github/workflows/train.yml` (new) — `workflow_dispatch` with `arm`, `version`, `repeat` and `fold` inputs; a matrix over the 25 folds when `repeat` and `fold` are unset; artifact upload of each fold's directory.
  - `ml/README.md` — the interpreter version, the install command, how to verify the environment, and which environment a published result comes from.
  - `docs/architecture/ml-implementation-map.md` — B1's entry gains the environment it was missing.
- Does NOT include:
  - Running an arm. This gives it somewhere to happen; #216 is where it happens.
  - Any training recipe parameter, or the input pipeline (SPEC 0050).
  - A self-hosted runner, a GPU, or any change to `ml/requirements.txt`.
  - Aggregating fold artifacts into an arm's `metrics.json`. `src.evaluate` already does that from stored predictions; wiring the download side is part of #216.
  - Committing any artifact.

## Acceptance Criteria

- the_readme_names_the_interpreter_version: `ml/README.md` names Python 3.12 and the install command, rather than a bare `python -m venv`.
- the_pin_check_passes_in_the_documented_environment: `ml/tests/test_requirements.py` passes rather than skips when the documented steps are followed.
- a_dispatched_run_takes_the_arm_and_the_version: the workflow accepts `arm` and `version` as inputs and passes them to `src.train`.
- a_dispatched_run_can_train_one_fold: given `repeat` and `fold`, exactly one job runs and trains that fold.
- a_dispatched_run_covers_every_fold_by_default: with `repeat` and `fold` unset, the matrix is the 25 folds of k = 5 and R = 5, taken from `ml/config.yaml` rather than written twice.
- every_job_uploads_its_fold_directory: each job uploads the fold's artifacts, named by arm, repeat and fold.
- the_record_says_which_environment_is_canonical: `ml/README.md` states that a published result comes from CI and that a local run is for iteration.

## Reproducibility

```sh
cd ml
/path/to/python3.12 -m venv .venv
.venv/Scripts/python -m pip install --upgrade pip
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m pytest tests/test_requirements.py -q   # passes, not skips
.venv/Scripts/python -m pytest tests/ -q                       # 434 passed, 0 skipped
```

Measured on this machine, Python 3.12.13, `tensorflow==2.21.0`, no GPU, after SPEC 0050's cache landed. The whole suite is **434 passed, 0 skipped in 275 s**.

**One fold, repeat 0 fold 0 of `v1`, arm `cnn`** — the first training this repository has ever completed. Its `cost.json` records five trainings, four inner selection fits and the refit:

```
213.1  109.2  124.5  297.0  186.6   seconds
```

**930.4 s, or 15.5 minutes per fold.** At 25 folds that is **6.5 hours per arm**, which is the number the matrix design rests on: a fold uses 4 % of a GitHub-hosted job's six-hour ceiling, so the per-fold split has a margin of roughly twenty-three times rather than a narrow fit. Before the cache, one fold had not finished its four inner fits after an hour.

## Risks and Assumptions

- **Assumption: one fold fits in a GitHub-hosted job.** It is the load-bearing assumption of the matrix design, and it is measured rather than estimated. If a fold ever approaches six hours — a larger backbone, more epochs — the matrix has to split further, and the measurement in the pull request is what a later reader compares against.
- **Assumption: 25 jobs per arm is an acceptable Actions cost.** Four arms is 100 jobs. If minutes become binding, the self-hosted runner rejected above is the next option, and it costs the reproducibility this spec is buying.
- **Risk: a local result gets published because the numbers match.** They will match; the run is seeded and deterministic. The defence is a statement in the record, not a mechanism, and that is a real weakness — nothing prevents it, and `runtime.json` records enough that a reader can tell after the fact.
- **Risk: the runner image changes under us.** `ubuntu-latest` moves, and a compiler or BLAS change can move a floating-point sum. `runtime.json` records the library versions but not the runner image; pinning the image is the fix if two runs ever disagree, and it is not done pre-emptively because it trades a real maintenance cost against a hypothetical.
- **What would invalidate this spec:** a decision to train somewhere other than CPU CI — a GPU, a self-hosted runner, or a managed service — each of which changes what "the canonical environment" names.
