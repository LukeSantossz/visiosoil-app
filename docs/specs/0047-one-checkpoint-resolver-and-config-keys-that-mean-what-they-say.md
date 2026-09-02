# SPEC: refactor(ml): resolve the model checkpoint in one place and name the config keys for what they hold

## Problem

Model checkpoint resolution is spelled out in `export.py` while `train.py` repeats the filename as a literal, and three `ml/config.yaml` names mislead a reader: `_range` means a scalar for two keys and a `[lo, hi]` pair for three others, and `project.version` is required, read by nothing, and collides in meaning with `data.dataset_version` and the CLI's `--version` (#30).

## Design Decision

One function, `find_model_checkpoint(output_dir)`, in `ml/src/model_paths.py`, returning the `.keras` checkpoint or falling back to `.h5` and raising a `FileNotFoundError` naming both paths. `export.py` calls it, and `train.py` writes through the same module's `CHECKPOINT_FILENAME` rather than repeating the string. A new module rather than a home in `model.py` or `config.py`: `model.py` imports TensorFlow at module scope and `src.crossval` must stay readable without it, while `config.py` resolves configured paths and knows nothing about what a training writes into one.

**The scalar augmentation keys are renamed** to say what they hold: `rotation_range` becomes `rotation_degrees` and `translation_range` becomes `translation_fraction`. The `_range` suffix now marks exactly the three keys that carry a `[lo, hi]` pair, which is what `_RANGED_AUGMENTATION_KEYS` already listed — so the name and the validator agree instead of contradicting each other. **`project.version` is removed** rather than renamed: it is read by nothing, so removing it is the smaller change, and a third thing called "version" beside the dataset version and the run version is worth deleting rather than re-spelling.

Renaming a configured key is breaking for any stored `config.json`. That is why it happens now: `train_fold` writes the resolved config into every fold directory, and no fold has ever been produced from real data, so there is no snapshot to break. A config carrying an old key is **refused by name**, not silently defaulted — a rename that falls back to a default trains on augmentation the operator did not ask for and reports nothing.

`preprocess.py` gains the sentence explaining why the rotation divisor is 360: Keras' `RandomRotation` takes its factor as a fraction of a full turn, so degrees over 360 is the conversion, and the 180 a reader might expect would double every rotation.

## Alternatives Considered

- **Put `find_model_checkpoint` in `model.py`.** Rejected. That module imports TensorFlow at module scope, and the artifact layout has to stay readable where TensorFlow cannot be installed — the property `src.crossval` was built around and `src.evaluate` depends on.
- **Put it in `config.py` beside `resolve_paths`.** Rejected. `resolve_paths` turns configured relative paths into absolute ones; which filename a training wrote inside one is not a fact about configuration, and putting it there would make `config.py` the place people add unrelated path helpers.
- **Keep `_range` on every key and document the split in a comment.** Rejected. The split is already hardcoded in `_RANGED_AUGMENTATION_KEYS`, so a comment would be a third statement of the same fact and the one most likely to rot. A name that has to be explained is the defect.
- **Accept the old key names as aliases for one release.** Rejected. There is no release and no stored config to migrate — the compatibility window would protect nothing, and an alias that silently maps `rotation_range` to `rotation_degrees` is indistinguishable from the typo it would also accept.
- **Rename `project.version` to `project.config_schema_version` and validate against it.** Rejected as out of proportion. Nothing versions the config schema today and nothing would read it, so this trades a key nobody reads for a key nobody reads plus a validator to maintain. If a schema version is ever needed, it arrives with the code that reads it.
- **Leave `project.version` in place, since it is harmless.** Rejected. It is required by `load_config`, so every fixture and every stored config carries it, and a reader has to work out that it means nothing. That cost is paid on every read.

## Scope

- Includes:
  - `ml/src/model_paths.py` (new) — `CHECKPOINT_FILENAME`, `LEGACY_CHECKPOINT_FILENAME`, `find_model_checkpoint`.
  - `ml/src/export.py` — call the helper instead of resolving inline.
  - `ml/src/train.py` — save through `CHECKPOINT_FILENAME`.
  - `ml/src/config.py` — drop `project` from the required top-level keys; rename the two scalar keys; refuse a config carrying an old name.
  - `ml/src/preprocess.py` — read the renamed keys; explain the 360 divisor.
  - `ml/config.yaml` — the renames, and `project.version` removed.
  - `ml/tests/` — one test per criterion below, and the fixtures carrying the old key names.
- Does NOT include:
  - Changing which checkpoint is preferred, or adding a `best_model.keras` to the order — #26's proposal, which SPEC 0042's nested selection refuses.
  - Changing any augmentation value, or the set of augmentations (ADR 0018 closed it).
  - The `[lo, hi]` keys, their validator, or `contrast_range`'s symmetry rejection.
  - `project.name`, which stays.
  - Any change under `lib/`.

## Acceptance Criteria

- one_resolver_is_called_by_every_reader: no module resolves a checkpoint path inline; `export.py` reaches `find_model_checkpoint` and `train.py` writes through `CHECKPOINT_FILENAME`, asserted against the modules' own source so a re-inlined copy fails.
- resolver_prefers_keras_over_h5: with both present, the `.keras` path is returned.
- resolver_falls_back_to_h5: with only `.h5` present, that path is returned.
- resolver_failure_names_both_paths: with neither present, `FileNotFoundError` names the `.keras` and the `.h5` path it tried.
- resolver_needs_no_tensorflow: the module imports without TensorFlow installed, so reading an artifact layout never reaches the training stack.
- scalar_augmentation_keys_carry_no_range_suffix: `ml/config.yaml` declares `rotation_degrees` and `translation_fraction`, and `_RANGED_AUGMENTATION_KEYS` names exactly the keys that hold a pair.
- an_old_augmentation_key_is_refused_by_name: a config carrying `rotation_range` or `translation_range` fails to load, naming the old key and its replacement, rather than defaulting the new one to zero.
- augmentation_layers_read_the_renamed_keys: the rotation and translation layers are built from the renamed keys, with the same values producing the same layers as before.
- project_version_is_not_required: `load_config` accepts a config with no `project.version`, and no module reads one.
- rotation_divisor_is_explained: `preprocess.py` states why the divisor is 360 rather than 180.

## Reproducibility

```sh
cd ml
python -m pytest tests/ -q
python -m pytest tests/test_config.py tests/test_preprocess.py tests/test_model_paths.py -v
```

```sh
flutter analyze && flutter test
```

No seed and no dataset: every criterion is over configuration parsing, string construction and file existence in a temporary directory. `resolver_needs_no_tensorflow` is asserted by the module's imports rather than by an environment, so it holds in CI where TensorFlow is installed as well as locally where it is not.

## Risks and Assumptions

- **Assumption: no stored `config.json` carries the old keys.** Verified rather than assumed: `train_fold` is the only writer, `ml/data/splits/` and `models/` are git-ignored, and no fold has been produced from real data. If one existed, `an_old_augmentation_key_is_refused_by_name` is what would tell its owner, by name, instead of training on a silently defaulted value.
- **Assumption: the `.h5` fallback is still worth keeping.** Nothing in this repository writes `.h5`; it is carried forward unchanged because removing it is a separate decision from extracting the resolver, and this change is meant to move code rather than to change what it does.
- **Risk: the source-level assertion in `one_resolver_is_called_by_every_reader` is a proxy.** Reading a module's text for the absence of an inlined resolver is weaker than executing it, and it cannot see a resolver written in a shape it does not recognise. It is paired with the behavioural criteria above, which do execute; the source check exists only to stop the duplication coming back, which is the thing #30 is about.
- **What would invalidate this spec:** a decision to keep more than one checkpoint per fold — #26's `best_model.keras`, which SPEC 0042 currently refuses — which would make the resolver's job a choice rather than a lookup.
