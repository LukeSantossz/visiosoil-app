# SPEC: fix(ml): close the keras model-loading advisories

## Problem

Dependabot reports seven open advisories against `keras==3.14.0` in `ml/requirements.txt` — two high, four moderate, one low — every one of them a model-loading flaw fixed in 3.15.0, and this repository calls `tf.keras.models.load_model` at `ml/src/export.py:39`.

## Design Decision

**Raise the pin to `keras==3.15.1` and change nothing else.**

`tensorflow==2.21.0` requires only `keras>=3.12.0`, with no upper bound, so the
bump is compatible with the rest of the pinned stack and no other pin moves.

**What the advisories actually reach here.** All seven need a hostile model file
to be loaded: HDF5 shape bombs and virtual datasets, symlink traversal during tar
extraction, `Lambda` deserialization escaping safe mode, and `TorchModuleWrapper`
unpickling. The sink exists — `export.py` loads a checkpoint, and
`model_paths.py:22` still names a legacy `model.h5` — but what it loads is what
`train.py:285` wrote minutes earlier under the same repository. **The shipped
application is not exposed at all**: it runs TFLite through `InferenceService` and
never touches Keras.

So the exposure is a local-file-trust question rather than a remote-input one,
and the honest statement of severity is lower than the advisory labels suggest in
isolation. The bump is still worth taking: it is one line, it costs nothing that
matters, and leaving seven open advisories on a public repository's default branch
so that a reader has to reconstruct this reasoning is worse than fixing them.

**The cost is one latent trap, and it is the reason this is not a spec-lite.**
Every one of the 100 folds SPEC 0057 computed recorded `keras: 3.14.0` in its
`runtime.json`. Those records are not invalidated — `fold_reuse_state` compares
the configuration, the manifest digest, the arm and the control flag, and
deliberately **not** the library versions, so the E0 gate can still reuse the
`cnn` arm SPEC 0057 paid 46.5 hours for. What changes is what happens if a fold
of an already-computed arm ever has to be recomputed: it would record 3.15.1
beside siblings recording 3.14.0, and `require_uniform_runtime` refuses an arm
whose folds disagree. The arm would then need `--force`, which discards all 25.

That trap is created by this change and is recorded here so that whoever meets it
knows why, rather than discovering an unexplained refusal after the E0 gate has
already started.

## Alternatives Considered

- **Leave the pin at 3.14.0.** Rejected. The advisories are real and the fix is a
  version number; declining it would require arguing that the sink is
  unreachable, and it is not — `export.py` reaches it, and the legacy `model.h5`
  path widens rather than narrows the surface.
- **Pin to `>=3.15.0` rather than an exact version.** Rejected. Every other entry
  in this file that governs a recorded runtime is exact, and `runtime.json`
  records the resolved version, so a floating pin would let two machines record
  different versions from the same file — which is the failure
  `require_uniform_runtime` exists to catch.
- **Take 3.15.0 rather than 3.15.1.** Rejected. 3.15.0 is the first patched
  version and 3.15.1 is the current one in the same minor; taking the older of two
  equally compatible releases buys nothing.
- **Also remove the legacy `model.h5` path to shrink the surface.** Rejected for
  this spec. It is a behaviour change to loading, not a dependency fix, and it
  would mix a refactor into a security bump. If it is wanted, it is its own spec.
- **Re-run the D6 arms under the new pin so the recorded stack matches the
  requirements file.** Rejected. It is 46.5 hours of GPU time to change a version
  string in a provenance record, and the result would be identical under
  determinism.

## Scope

- Includes:
  - `ml/requirements.txt` — `keras==3.14.0` becomes `keras==3.15.1`.
  - `docs/ml/transported-population-sensitivity.md` — one line noting that the
    verdict's arms were computed under Keras 3.14.0 and that the pin has since
    moved, so the provenance table stays true rather than becoming a claim about
    a stack the file no longer names.
- Does NOT include:
  - Any other pin in `ml/requirements.txt`.
  - Removing the legacy `model.h5` loading path.
  - Re-running any arm, or touching anything under `ml/models/`.
  - Any change under `lib/`, or to the TFLite path the application uses.
  - `pubspec.yaml` and the Dart dependency graph, which these advisories do not
    concern.

## Acceptance Criteria

- the_pin_is_the_first_patched_version_or_later: `ml/requirements.txt` names a
  `keras` version at or above 3.15.0.
- the_rest_of_the_stack_does_not_move: `pip install -r ml/requirements.txt`
  resolves with TensorFlow still at 2.21.0, numpy at 1.26.4, scikit-learn at
  1.5.2 and pillow at 10.4.0 — asserted by reading the installed versions back,
  not by reading the file.
- the_ml_suite_passes_under_the_new_pin: `pytest tests/ -q` in `ml/` passes and
  its summary reports **zero skipped**, checked by the command below rather than
  read off the output by eye. *Corrected after R3: the original asked for the
  dataset-gated tests to execute rather than skip but gave no way to fail on a
  skip, and those tests skip by design when TensorFlow or the dataset is absent —
  so a run in the wrong environment would have satisfied it silently.*
- the_recorded_verdict_stays_true: the sensitivity report's provenance still says
  the arms ran under Keras 3.14.0, and the document says the pin has since moved.
- no_open_advisory_remains_for_keras: the Dependabot query filtered to
  `state=open`, `ecosystem=pip` and `package=keras`, paginated, returns nothing.
  *Corrected after R3: the original counted every open alert on the first page,
  which neither isolates Keras nor sees past page one.*

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pip install -r requirements.txt

# Fails on a skip rather than leaving it to the reader's eye.
.venv/Scripts/python.exe -m pytest tests/ -q -rs | tee ml-suite.log
grep -qE "[0-9]+ skipped" ml-suite.log && { echo "tests skipped"; exit 1; }

# Keras only, every page.
gh api --paginate "/repos/LukeSantossz/visiosoil-app/dependabot/alerts?state=open&ecosystem=pip&package=keras" --jq "length"
```

## Risks and Assumptions

- **Risk: a partially recomputed arm becomes non-uniform.** Described above. It
  bites only if a fold of an already-complete arm is recomputed under the new
  pin; the E0 gate reusing all 25 folds untouched does not trigger it.
- **Risk: Keras 3.15.1 changes training numerics.** Determinism is on and the
  folds already computed are not re-run, so nothing already measured moves. A
  future arm trained under 3.15.1 is a different runtime from one trained under
  3.14.0, and `require_uniform_runtime` is what makes that visible rather than
  silent.
- **Assumption: `tensorflow==2.21.0` accepts Keras 3.15.1.** Read from the
  published metadata — `keras>=3.12.0`, no upper bound — and the criterion above
  tests it by resolving the file rather than trusting the reading.
- **What would invalidate this spec:** a Keras 3.15.x release that TensorFlow
  2.21.0 refuses, or an advisory against 3.15.1 itself.
