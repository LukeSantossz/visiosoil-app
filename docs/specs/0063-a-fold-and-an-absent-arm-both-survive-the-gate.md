# SPEC: fix(ml): reuse a fold drawn on another machine, and record an arm that did not run

## Problem

Twenty-six and a half hours of completed `cnn` folds cannot be reused because
the reuse check compares four machine-local path strings, and a contrast family
naming one arm that was never run computes none of its contrasts instead of
recording that arm as not executed.

## Design Decisions

Two defects, both found while auditing what SPEC 0044's gate still needs, both
blocking that gate today, and both small. They ship together because each is a
one-function change to the same lane and neither is worth a pull request alone.

### The reuse check compares where the files are, not what the experiment is

`fold_reuse_state` (`crossval.py:80`) marks a fold stale unless its recorded
`config.json` is **deep-equal** to the live configuration. That configuration has
been through `resolve_paths`, which rewrites four keys to absolute paths —
`data.raw_dir`, `data.splits_dir`, `data.datasets_dir` and `export.output_dir`.
A fold computed on another machine therefore differs in four strings that say
where a directory sits, and in nothing else.

This is not hypothetical. SPEC 0057's `cnn` arm ran in WSL2 on this machine and
its 25 fold directories are intact at `/home/lucas/visiosoil-app/ml/models/v1/`.
Compared against the live configuration, the *only* differences are those four
paths: the class list, the evaluation block, the preprocessing geometry, the
augmentation, the model, the training recipe and the seed are identical, and
`predictions.json` records the same `manifest_digest`,
`49cc469f8923f5f41e5cdba5c6413712a40559479d7092ccdc0efd3e13af59f9`. The gate
would recompute 26.5 hours of GPU training to arrive at the same numbers.

**The comparison is narrowed, not the file.** `config.json` keeps recording the
resolved paths, because which machine produced a fold is provenance worth having
and it is what `runtime.json` cannot say. What changes is that the four keys are
excluded from the equality test, by name.

**Excluded by name rather than by shape.** A rule like "ignore anything that
looks like a path" would silently absorb a future key whose value happens to be
a path and whose difference does matter. The four are listed, and a test asserts
the list is the four `resolve_paths` actually rewrites, so adding a fifth to that
function without deciding about it here fails.

**What makes the exclusion safe is that something else already guards the data.**
The worry is that two different `datasets_dir` values point at genuinely
different datasets, and the path is what would have caught it. It is not:
`fold_reuse_state` compares `manifest_digest` before it reaches the
configuration at all (`crossval.py:55`), and that digest is over the dataset
manifest's own bytes. A different dataset under the same path is caught; the
same dataset under a different path is what this stops refusing.

### An arm that did not run is recorded, not raised

`contrast_results` raises `ValueError` on the first contrast naming an arm with
no predictions, before computing any contrast at all. Run today against this
repository, `evaluate('v1', 'descriptors', contrasts=True)` raises on `cnn` and
returns nothing — including `descriptors_vs_control`, whose two arms are both on
disk.

SPEC 0044's acceptance criterion says the opposite: *"an arm absent from
`metrics.json` is reported as not executed, and no contrast is computed for
it"*. Its decision rule makes that a first-class outcome rather than an error —
condition 1 is **Executed**, and the spec says an arm that could not be run *"is
not executed, which is its own recorded outcome and is never reported as having
lost a comparison"*. The gate is expected to reach that state: the encoder arm's
adoption is decided partly on whether it ran at all.

So a contrast naming an absent arm is recorded with the arm named and no
statistic, and every other contrast is computed.

**The Holm correction is applied over the contrasts that were computed**, and the
direction of that choice is worth stating precisely because it is easy to get
backwards. Holm compares the *i*-th smallest p-value against `alpha / (n - i +
1)`, so a larger family means a **smaller** threshold for every member. Including
a test nobody performed would therefore make the real contrasts harder to reject
— it would penalise them for an absence rather than for evidence.

**This is a deviation from the pre-registered family, and it is one the verdict
has to record.** SPEC 0044 registers four contrasts before the first run, and
correcting over three is not what was registered. The justification is that Holm
corrects for multiplicity of *tests conducted*, and a contrast with no data is
not a test; the honest form of that is to say so in the verdict, naming which
contrasts entered the correction and which did not. This specification makes the
behaviour correct and leaves the recording to the verdict, which is the next
specification's.

**One implementation constraint, found by reading the code rather than assumed.**
`_apply_holm_within_families` reads `contrast["p_value"]` unconditionally, so a
not-executed entry cannot simply be appended to the same list with that key
missing — it would raise `KeyError` inside the correction. The not-executed
entries are therefore kept out of the list Holm is given, which is the same thing
the paragraph above argues for on statistical grounds and happens to be what the
existing code forces. The two agree, and the coincidence is worth naming so the
next reader does not "simplify" it back.

**The deviation is already visible in the artifact.** Each corrected contrast
records `family_size`, which will read `2` where the registration declared three
primary contrasts. Nothing new has to be invented to expose the adjustment; what
the verdict adds is the sentence saying why.

A `--contrast <name>` flag already exists and narrows the registry to one entry,
so the three runnable contrasts can be computed one at a time today. That is a
workaround an operator has to know, and it is not the criterion.

## Alternatives Considered

- **Store the unresolved configuration in `config.json` instead.** It is the
  tidier shape, and it is useless here: the 25 fold directories that exist were
  written with resolved paths, so a fix on the writing side recovers none of
  them and the 26.5 hours stay lost. The comparison is where the change has to
  happen.
- **Compare only a hand-picked subset of keys — classes, evaluation,
  preprocessing, model, training.** Rejected: an allowlist silently ignores
  every key added later, which is the failure mode of a reuse check that is
  supposed to be conservative. A denylist of four named keys fails closed for
  anything new.
- **Re-root the recorded paths and compare, as SPEC 0061 does for the fold
  manifest.** Rejected: there is nothing to re-root against. The fold manifest's
  paths are relative to a dataset root the reader knows; a configuration's
  `raw_dir` is an absolute location with no declared base, and inventing one
  would be guessing where a checkout ended.
- **Let `--force` cover it.** Rejected, and it is the trap rather than the
  remedy: `--force` recomputes every fold it is given, so using it to accept
  foreign folds would discard exactly the folds being recovered.
- **Raise on an absent arm but catch it in a gate runner.** Rejected: it puts
  the criterion's behaviour in a caller that does not exist yet, and leaves the
  library refusing a state its own specification calls an outcome.
- **Compute the absent arm's contrast against an empty correctness map.** It
  would produce a p-value of 1.0 and read as a tie. That is the precise failure
  the criterion names — an arm that did not run reported as having not lost.

## Scope

- Includes:
  - `ml/src/crossval.py`: a named constant for the four machine-local
    configuration keys, and `fold_reuse_state` comparing the configuration with
    those excluded.
  - `ml/src/evaluate.py`: `contrast_results` records a contrast whose arm has no
    predictions as not executed, naming the arm, and computes the rest; Holm is
    applied over the computed contrasts only.
  - `ml/tests/`: one test per acceptance criterion below.
- Does NOT include:
  - Changing what `config.json` records. The resolved paths stay, as provenance.
  - Copying the WSL2 fold directories, or running any arm. This makes the reuse
    possible; performing it is the gate's own run.
  - The cross-arm library-stack question. Both existing arms recorded Keras
    3.14.0 and the repository pins 3.15.1; the Developer decided on 2026-09-11
    to run the gate under 3.14.0, and `require_uniform_runtime` is per-arm by
    design. Recording that belongs to the gate's verdict, not here.
  - The descriptor ablation, the verdict writer, the decision rule and the gate
    runner. Four of SPEC 0044's criteria have no implementation; they are the
    next specification, not this one.
  - Reconciling SPEC 0044's criterion 7, which says `metrics.json` carries the
    contrast statistics while the code writes them to `contrasts.json`. It is a
    wording question about where the verdict reads from, and it belongs with the
    verdict.

## Acceptance Criteria

- `a_fold_whose_config_differs_only_in_paths_is_reusable` — a fold recorded with
  different `raw_dir`, `splits_dir`, `datasets_dir` and `export.output_dir`, and
  an otherwise identical configuration, classifies as `reusable`.
- `a_fold_from_another_configuration_is_still_stale` — changing any other key,
  including one nested inside `evaluation` or `training`, still classifies as
  `stale`, so the exclusion has not blanket-passed the check.
- `the_excluded_keys_are_exactly_what_resolve_paths_rewrites` — the named
  constant equals the set of keys `resolve_paths` makes absolute, so a fifth
  resolved key cannot be added without a decision here.
- `a_fold_from_another_manifest_is_still_stale` — the digest check is untouched
  and still refuses a fold drawn over different data, whatever its paths say.
- `an_arm_that_did_not_run_is_recorded_as_not_executed` — a contrast naming an
  arm with no predictions is recorded with that arm named and the outcome
  `not_executed`, and nothing raises.
- `a_not_executed_contrast_carries_no_statistic` — it has no p-value, no
  observed difference, no minimum detectable effect and no sign.
- `the_contrasts_whose_arms_ran_are_still_computed` — in the same call, every
  contrast whose two arms both have predictions is computed.
- `holm_corrects_over_the_computed_contrasts_only` — a family holding one
  computed and one not-executed contrast corrects as a family of one, and the
  computed contrast records `family_size` 1, so the deviation from the
  registered family is legible in the artifact rather than only in prose.
- `a_not_executed_contrast_does_not_reach_the_correction` — the correction is
  never handed an entry without a `p_value`, which today raises `KeyError`
  inside it.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/test_fold_reuse.py tests/test_crossval.py -q
.venv/Scripts/python.exe -m pytest tests/ -q
```

No randomness. Python 3.12 with `ml/requirements.txt`. The WSL2 fold directories
this recovers are at `/home/lucas/visiosoil-app/ml/models/v1/cnn/`; whether they
are accepted is verifiable after this change with

```sh
.venv/Scripts/python.exe -c "from src.crossval import plan_arm_run; ..."
```

which is evidence for the pull request rather than an acceptance criterion,
because it needs those directories present.

## Risks and Assumptions

- Assumption: the four keys `resolve_paths` rewrites are the only machine-local
  values in the configuration. `the_excluded_keys_are_exactly_what_resolve_paths_rewrites`
  asserts it rather than trusting it. What would invalidate it: a configuration
  key that is machine-local without going through `resolve_paths` — at which
  point a fold would be refused for a reason no one intended, loudly.
- Assumption: `manifest_digest` is a sufficient guard that two folds describe
  the same data. It is a SHA-256 over the dataset manifest's bytes and is
  compared before the configuration, so the case the path was incidentally
  guarding is already covered.
- Risk, accepted: a recovered fold's `runtime.json` may record a different
  library stack from the machine reading it. `require_uniform_runtime` refuses
  an arm whose own folds disagree, which is the guarantee that matters; across
  arms it is deliberately not refused, and the gate's verdict is where that gets
  recorded. This change does not weaken either.
- Risk: recording a not-executed contrast makes it possible to publish a verdict
  that quietly omits an arm. The mitigation is not here — it is SPEC 0044's
  criterion that the verdict state each decision-rule condition by name, and the
  next specification implements it.
- **Risk, and the sharpest one here: correcting over three contrasts instead of
  the four that were pre-registered is a deviation from the registration.** It is
  the right statistical call — Holm corrects for tests conducted, and a contrast
  with no data is not one — but a pre-registration exists precisely so that the
  analysis cannot be adjusted after the numbers are seen, and this adjusts it.
  What keeps it honest is that the rule is fixed **now**, before the gate runs,
  and that the verdict must name which contrasts entered the correction. What
  would invalidate the reasoning: a reading under which the registered family is
  the unit regardless of execution, which would make every contrast in the gate
  stricter whenever any arm failed to run — penalising the arms that did run for
  the failure of one that did not.
- What would invalidate this spec: discovering that the WSL2 folds differ from
  the live configuration in some key beyond the four paths, which would mean the
  26.5 hours are not recoverable and the first half of this change buys nothing.
  The comparison above was run and found exactly four differences.
