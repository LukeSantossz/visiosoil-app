# SPEC: test(inference): report a folder of field photographs through the descriptor path

## Problem

SPEC 0167's field session and every later check against real photographs must state each photograph's outcome, scale and disc as `docs/ml/sheet-reader-real-photographs.md` does, but the run that produced that table was a throwaway test that was never committed, so the next session has no reproducible way to produce its table.

## Design Decision

A committed `flutter test` file runs every JPEG in a folder named by the `VISIOSOIL_PHOTOS` environment variable through `InferenceService.runInference` with the shipped contract (`assets/models/spec.json`) and `a4SheetMeasurer`, the path the app runs, and prints one Markdown table in the shape of the existing per-photograph table, followed by a count of the photographs classified. Without the variable it is skipped, so `flutter test` and CI are unchanged. The table is built by a small pure function, unit tested on its own, and the runner only collects the reports and prints. The scale and the disc are read by wrapping `a4SheetMeasurer` in a closure that keeps the measurement it returns, which needs no change to `lib/`.

## Alternatives Considered

- **A Dart command-line tool under `tool/`, run with `dart run`.** Rejected: `InferenceService` imports Flutter (`rootBundle`), so the descriptor path cannot load outside the Flutter test runner without moving code in `lib/`, which this change has no reason to touch.
- **Reading each outcome off the capture preview's chip on the phone.** Rejected as the record: it is transcribed by hand, a saved record keeps no cause, and it cannot be rerun after a reader change to give a before-and-after column, as SPEC 0140 and SPEC 0144 did.
- **An export screen in the app that writes the outcomes.** Rejected: it adds product surface for a development check.

## Scope

- Includes:
  - `test/field_session/field_session_report.dart`: the pure function that turns the collected rows into the Markdown table and the count.
  - `test/field_session/field_session_report_test.dart`: its unit tests.
  - `test/field_session/field_session_test.dart`: the runner, skipped when `VISIOSOIL_PHOTOS` is unset.
  - `docs/ml/sheet-reader-real-photographs.md`: a paragraph under "Reproducing it" naming the command, and how the photographs come off the phone (the record's share action sends the stored photograph, whose pixels are byte-identical to the capture).
- Does NOT include:
  - Any change under `lib/`, to the reader, the contract, or the classification.
  - Running the field session or recording its result, which SPEC 0167 owns and the Developer runs.
  - Judging the pass threshold: the report gives the count, and SPEC 0167's 9 of 10 is applied by the reader of the report.
  - Annotated sheet corners or any comparison against expected outcomes, which `a4_sheet_photos_test.dart` keeps for its six fixtures.
  - A before-and-after column. Running the command on two commits gives both.

## Acceptance Criteria

- `lists_each_photograph_in_name_order`: the table has one row per photograph, sorted by file name, whatever order the rows are given in.
- `a_classified_photograph_shows_its_class_and_confidence`: a successful report shows the texture class and its confidence as a whole percentage.
- `a_refused_photograph_shows_its_cause`: a failed report shows the cause by its enum name, such as `soilRegionTooSmall`.
- `the_sheet_found_shows_scale_and_disc`: a row whose measurement was taken shows the scale in mm/px to four decimals and the disc in mm to one decimal; a row without one leaves both blank.
- `the_count_closes_the_report`: the line after the table reads `N of M classified`.
- `an_empty_folder_is_named`: a folder with no JPEG fails the runner with a message naming the folder, rather than printing an empty table.
- `skipped_without_a_folder`: with `VISIOSOIL_PHOTOS` unset, `flutter test test/field_session` reports the runner as skipped and passes.
- `runs_the_committed_photographs`: `VISIOSOIL_PHOTOS=test/fixtures/sheet_photos` prints one row for each of the six JPEGs there and no other file.

## Reproducibility

```sh
flutter test test/field_session
VISIOSOIL_PHOTOS=<folder> flutter test test/field_session/field_session_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0. Nothing in the path is random.

## Risks and Assumptions

- Assumption: the desktop run gives the phone's outcome, because the descriptor path is pure Dart over the decoded pixels and the shared photograph is the stored one.
- Assumption: JPEG is the only format a capture produces, so files are matched by the `.jpg` and `.jpeg` extensions, case-insensitive.
- Risk: full-resolution originals take seconds each in the test runner. The runner gets a timeout long enough for a session of tens of photographs, and the count is what matters, not the speed.
- What would invalidate this spec: the app's capture path diverging from `runInference` with `a4SheetMeasurer`, which would make the desktop report describe a different path.
