# SPEC: refactor(ml): separate the archive's class vocabulary from the model's class list, and drop Siltosa from the model's

## Problem

`ml/config.yaml` still declares five classes, so fold creation for dataset version `v1` refuses — Siltosa holds three splittable sample groups against `evaluation.k: 5` — and nothing downstream of it can run (#211).

## Design Decision

Siltosa is removed from `ml/config.yaml`'s `classes` and from `SoilTextureLabels.ordered`, leaving Arenosa, Media, Muito Argilosa, Argilosa in their existing relative order. That is what ADR 0016 decided and what `ml/src/dataset.py`'s own refusal message names as the remedy.

**The decision this spec actually takes is the one the ticket did not see.** `cfg["classes"]` is read today for two different jobs: it is the model's output order, *and* it is the vocabulary `read_manifest` validates every manifest row against. Those were the same list only by coincidence. Dropping Siltosa from one drops it from both, and `read_manifest` would then reject the six Siltosa rows the archive delivered — so `validate_dataset`, `admit_images`, `ingest_archive` and fold creation would all fail on a dataset that is exactly as it should be. **The two lists are therefore separated**: `ARCHIVE_CLASSES` in `ml/src/manifest.py` is the five classes the delivered archive contains, and `cfg["classes"]` is the four the model emits.

The split follows the existing seam rather than inventing one. `ARCHIVE_CLASS_BY_FOLDER` in `ml/src/ingest.py` already *is* the archive's vocabulary — it maps the five delivered folders to class names — so `ARCHIVE_CLASSES` is that list named, and a test asserts the two cannot drift apart. Every call site is then decided by which question it asks: *what may this manifest contain* takes `ARCHIVE_CLASSES`; *what does the model emit* takes `cfg["classes"]`.

**The three Siltosa sample groups stay in the manifest and never reach a fold.** ADR 0019 makes a dataset version a build product and SPEC 0040 ingests the whole archive, so deleting rows would make `v1` disagree with the archive it claims to be. They are excluded where the pool is built, by `manifest_class_images(manifest, cfg["classes"])`, which is a consequence of the class list rather than a second rule to keep in step.

**Model output index 2 changes meaning**, from Siltosa to Muito Argilosa. No artifact, prediction file or metric produced under the five-class list is comparable to one produced after this change. Nothing exists to invalidate — no model has ever been trained on real data — and `load_folds_for_config` refuses a fold manifest whose class list disagrees with the config, which is the guard that makes the change safe rather than silent.

## Alternatives Considered

- **Lower `evaluation.k` until Siltosa fits.** Rejected. Three groups needs k = 3, which SPEC 0042 rejected on its own terms, and it would keep a class whose defining fraction is not resolvable at the archive's measured millimetres per pixel — ADR 0016's other reason, which no value of k addresses.
- **Delete the Siltosa rows from the v1 manifest.** Rejected. A dataset version is a build product of the archive (ADR 0019); a version that silently holds less than what was delivered cannot be checked against it, and the rows remain usable by any arm that needs no texture label (#204).
- **Keep one class list and let `read_manifest` warn instead of reject on an undeclared class.** Rejected. Rejecting an undeclared class is what catches a typo in a manifest before it becomes a silently mislabelled row; weakening it to fix an unrelated problem trades a real guard for a convenience.
- **Add `data.archive_classes` to `ml/config.yaml`.** Rejected. The archive's vocabulary is a fact about the delivered data, not a choice an operator makes, and putting it in the config invites someone to edit it to make an error go away. It lives in code, beside the folder map it must agree with.
- **Derive `ARCHIVE_CLASSES` from `ARCHIVE_CLASS_BY_FOLDER.values()` at import.** Rejected, narrowly. It cannot drift, but it makes the archive's vocabulary a by-product of a mapping whose keys are the delivered directory names, and it puts the constant in `ingest.py`, which `manifest.py` must not import. Declared in `manifest.py` and asserted equal instead: the same protection, in the module that owns the manifest contract.
- **Remove the Siltosa colour from `SoilTextureColors`.** Rejected. ADR 0016 excludes Siltosa from the *first* model, not from the product, and the archive still holds those samples. The entry stays with the reason recorded beside it; `SoilTextureColors.all` derives its order from `SoilTextureLabels.ordered`, so an unused key changes nothing a caller sees.

## Scope

- Includes:
  - `ml/src/manifest.py` — declare `ARCHIVE_CLASSES`.
  - `ml/src/ingest.py` — no behaviour change; its folder map is asserted against `ARCHIVE_CLASSES`.
  - `ml/src/dataset.py`, `ml/scripts/validate_dataset.py`, `ml/scripts/admit_images.py`, `ml/scripts/ingest_archive.py` — each `read_manifest` call takes the archive vocabulary; each pool and coverage call keeps `cfg["classes"]`.
  - `ml/config.yaml` — four classes.
  - `lib/models/soil_texture_labels.dart` — the same four, in the same order.
  - `lib/core/theme/soil_texture_colors.dart` — the Siltosa entry keeps its colour and gains the reason.
  - The Dart and Python fixtures carrying a five-entry model-class literal.
- Does NOT include:
  - Removing any Siltosa row from the manifest, or changing `ingest.py`'s folder map.
  - Reading the class list from `spec.json` — that is A11 (#79), which turns `SoilTextureLabels` into a fallback.
  - Regenerating any committed artifact: `ml/data/splits/` is git-ignored, so the fold manifest is regenerated by running the command, not by committing a file.
  - Any change to `evaluation.k`, to the fold generator, or to the protocol.
  - The config key renames of #30.

## Acceptance Criteria

- config_declares_four_classes_without_siltosa: `ml/config.yaml` lists Arenosa, Media, Muito Argilosa, Argilosa, in that order, and no Siltosa.
- dart_label_list_matches_the_config_order: `SoilTextureLabels.ordered` is exactly those four in that order, asserted as a literal so a silent reordering fails.
- archive_vocabulary_covers_every_delivered_folder: `ARCHIVE_CLASSES` equals the set of values in `ARCHIVE_CLASS_BY_FOLDER`, so the two cannot drift.
- archive_vocabulary_is_a_superset_of_the_model_classes: every class in a loaded config is in `ARCHIVE_CLASSES`, so a config naming a class the archive cannot contain is caught.
- manifest_reading_accepts_a_siltosa_row_under_the_four_class_config: `read_manifest` parses a manifest holding Siltosa rows while the config declares four classes.
- siltosa_groups_reach_no_fold: over the real `v1` manifest, no group whose class is Siltosa appears in any fold's train or test side, in any repeat.
- fold_creation_succeeds_at_k_five: fold creation over the real `v1` manifest completes at `evaluation.k: 5`, with every class holding at least k splittable groups.
- a_five_class_fold_manifest_is_refused: a fold manifest drawn under the five-class list is refused against the four-class config rather than reused, naming the disagreement.
- colour_map_covers_exactly_the_label_list: `SoilTextureColors.all` yields exactly the four labels in order, and the retained Siltosa key changes nothing a caller sees.
- resolve_texture_label_reports_four_outputs: `InferenceService.resolveTextureLabel` is asserted against a four-class output, and index 2 resolves to Muito Argilosa.

## Reproducibility

```sh
cd ml
python -m pytest tests/ -q
python scripts/validate_dataset.py --version v1
python -c "from src.config import load_config, resolve_paths; from src.dataset import create_folds_for_config; cfg = resolve_paths(load_config()); create_folds_for_config(cfg, cfg['data']['splits_dir'])"
```

```sh
flutter analyze && flutter test
```

The dataset-dependent criteria — `siltosa_groups_reach_no_fold` and `fold_creation_succeeds_at_k_five` — run only where the ingested `v1` archive is present, which is a developer machine and never CI, per ADR 0019. SPEC 0043's audit reports them as dataset-gated, which is correct and is the state that spec exists to make visible. Fold assignment depends on the scikit-learn version as well as on `data.seed`; the pinned range is in `ml/requirements.txt`.

## Risks and Assumptions

- **Assumption: the archive's vocabulary is fixed at five.** ADR 0016 closed the dataset and SPEC 0041 withdrew the collection premise, so no sixth class can arrive. If one did, `ARCHIVE_CLASSES` and the folder map both change, and the criterion tying them together fails first.
- **Assumption: no stored artifact depends on the old index order.** Verified rather than assumed: no model has been trained on real data, `ml/data/splits/` is git-ignored, and no `predictions.json` exists in the repository.
- **Risk: a developer regenerates the fold manifest before changing the config.** The result is `load_folds_for_config` refusing it, which reads like a bug and is the guard working. The order is stated in Reproducibility, config first.
- **Risk: the two lists are confused at a call site added later.** The mitigation is that each has a name that says which question it answers, plus the superset criterion, which fails if a config names a class the archive cannot hold. Neither stops someone passing the wrong one to `read_manifest` in a way that is merely more permissive; that residue is real and is recorded rather than claimed away.
- **What would invalidate this spec:** a decision to train Siltosa after all, which would need ADR 0016 superseded rather than this spec edited, or A11 (#79) making `spec.json` the source of the label list, which turns the Dart constant into a fallback and leaves this split untouched.
