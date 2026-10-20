# SPEC: test(inference): score labelled field photographs and export them at the canonical scale

## Problem

The field-session runner (SPEC 0170) reports what the app read on each photograph but not whether it was right, and the classifier's refit runs in Python on another machine, which has no A4-sheet reader and so cannot measure the field photographs of 2026-10-19 itself.

## Design Decision

The runner reads a photograph's labels from its folder: `<root>/<class>/<sample>/*.jpg`, where `<class>` is one of the contract's classes and `<sample>` names the soil sample. A photograph directly under `<class>/` belongs to a sample named after the class. With labels, the table gains the expected class and whether the read matched, and the report closes with the accuracy per class and a confusion matrix over the photographs the app classified. Photographs refused are counted apart, by cause, so a refusal is never scored as a miss or a hit. A folder without class subfolders reports exactly as SPEC 0170 does.

With `VISIOSOIL_EXPORT=<dir>` set, every measured photograph is also written as the region the classifier reads. That region is the measurement's square resampled to the contract's canonical scale, as a PNG, together with one `manifest.json` row: file, class, sample, source photograph, measured mm/px, the disc's centre and diameter in canonical pixels, and whether reaching the canonical scale upsampled it. A photograph coarser than the canonical is resampled anyway and flagged `upsampled: true`. The runner never classifies it, as the app does not, and the Python side decides whether to use it. The canonical region is the boundary between the two languages: the Python patch grid (`src.patches.cut_patches`) cuts it with no resampling of its own.

## Alternatives Considered

- **Port the A4-sheet reader to Python.** Rejected: a second implementation of the reader that would have to be kept in step with the app's, for a dataset of 54 photographs.
- **Export only the patches.** Rejected: augmentation that rotates or flips the region, or recompresses it, has to act on the region and then cut the grid, so the patches would be cut from a different image than the one augmented.
- **Score refusals as misses.** Rejected: it would mix the capture's failures with the classifier's, and the refit is about the classifier.

## Scope

- Includes:
  - `test/field_session/field_session_report.dart`: labels from the folder tree, the expected and match columns, per-class accuracy, the confusion matrix, refusals counted by cause, and the export.
  - `test/field_session/field_session_report_test.dart`: the tests.
  - `test/field_session/field_session_test.dart`: `VISIOSOIL_EXPORT`.
  - `docs/ml/field-photographs-2026-10-19.md`: the labelled evaluation of 2026-10-19, with the burst-to-class mapping, the app's result, and the upsampling, blur and re-centring studies of this session, each with the numbers it gave.
  - A labelled copy of the 54 photographs in `Downloads/NewImages-labelled/<class>/<sample>/`, outside the repository. The original folder is left as it is.
- Does NOT include:
  - Any change under `lib/` or `ml/`.
  - Committing photographs or exported regions: the photographs carry their location, and together they weigh 142 MB.
  - The augmentation and the refit, which are SPEC 0175.

## Acceptance Criteria

- `labels_come_from_the_folders`: a photograph at `<root>/Media/S3/a.jpg` is expected `Media` from sample `S3`, and one at `<root>/Arenosa/b.jpg` is expected `Arenosa` from sample `Arenosa`.
- `an_unknown_class_folder_is_named`: a first-level folder that is not a contract class fails the runner, naming the folder and the contract's classes.
- `a_labelled_row_shows_expected_and_match`: a classified row shows the expected class and ✓ or ✗; a refused row shows the expected class and no mark.
- `accuracy_counts_only_classified_photographs`: with 3 of 4 `Argilosa` photographs classified, 2 of them right, the `Argilosa` line reads `2 of 3 classified right (1 refused)`.
- `the_confusion_matrix_has_every_class`: the matrix has one row and one column per contract class, in the contract's order, and its cells sum to the classified count.
- `an_unlabelled_folder_reports_as_before`: a flat folder gives SPEC 0170's table and count, with no labelled columns.
- `the_export_is_at_the_canonical_scale`: an exported region of a photograph measured at 0.0419 mm/px has the measurement square's size times 0.0419 / canonical, rounded as `resampleToCanonical` rounds, and its manifest row carries the disc's centre and diameter scaled by the same ratio.
- `a_coarse_photograph_is_exported_upsampled`: a photograph measured coarser than the canonical is exported at the canonical scale with `upsampled: true` and its measured mm/px, and is still reported as `photographTooCoarse`.
- `a_refused_photograph_is_not_exported`: a photograph whose sheet or disc was not measured has no PNG and no manifest row.

## Reproducibility

```sh
flutter test test/field_session
VISIOSOIL_PHOTOS=<labelled root> VISIOSOIL_EXPORT=<dir> flutter test test/field_session/field_session_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0. The export is deterministic: the same photographs give byte-identical PNGs and manifest.

## Risks and Assumptions

- Assumption: the bursts map to classes as the Developer stated on 2026-10-19: 15:01 Argilosa, 15:06 Muito Argilosa, 15:10 Media, 15:13 Arenosa, 16:59 to 17:00 Argilosa, each burst one soil sample.
- Assumption: Dart's `resampleToCanonical` and Python's `resample_to_canonical` agree, as the patch goldens already require, so a region exported here is the region Python would have resampled.
- Risk: five soil samples are too few to show that a refit generalises to new soils. The document says so, and SPEC 0175 measures by holding one sample out at a time.
- What would invalidate this spec: an exported region whose Python patches differ from the patches the app cuts from the same photograph.
