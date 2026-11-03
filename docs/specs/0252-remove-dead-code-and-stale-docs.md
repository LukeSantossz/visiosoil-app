# SPEC: chore: remove dead code and stale docs

## Problem

An audit of `main` at 10f4909 found code, a dependency and documents that nothing uses or that no longer describe the project:

- `lib/core/features/history/widgets/history_grid.dart` has had no caller since SPEC 0190 moved the history screen to `HistoryList`, which kept the paging and the "Mostrando os N registros" notice. Four test files still pin properties of the dead widget, so it keeps costing maintenance. Unlike `SyncEngine`, `ProxyResearchService`, `ImageQualityAnalyzer` and `ClassificationVerdict`, which are recorded as deliberate debt, nothing records it.
- Seven `AppStrings` constants are referenced nowhere: `errorReportTitle`, `themeChoiceSystem`, `themeChoiceLight`, `themeChoiceDark`, `themeChoiceSun`, `themeChoiceCaption` and `resultSaved`. Settings writes its row copy inline, as it does for every other row, so those constants only look like the source of the copy.
- `cupertino_icons` is a direct dependency that no file under `lib/` or `test/` imports.
- The README says schema v9 (it is v12), "20 files declaring 44 Riverpod providers" (24 files, 63 providers) and "12 shared widgets" (25). It also lists ADR 0008 (TFLite as the only runtime) without saying that ADR 0024 amended it and that v1 ships no ML runtime. The agents overlay, `docs/agents/project.md`, gives the same stale counts to `CLAUDE.md` and `AGENTS.md`.
- `docs/superpowers/plans/2026-11-01-retry-corpus-rejections.md` is a skill's working plan for SPEC 0251, and that spec is the record. It is the only file under `docs/superpowers/`.
- `docs/design/prototipo-v11/telas/` holds 12 PNGs and `docs/design/prototipo-v11/haptics.md` a document, each byte-identical to its copy under `docs/design/spec/`.
- A failed golden writes `test/core/theme/failures/`, and nothing ignores it, so it shows up as untracked.

## Design Decision

Delete what is dead, correct what is stale, and add two guards so the dead code cannot come back unnoticed:

- `test/standards/no_orphan_library_test.dart`: every Dart file under `lib/` except `main.dart` and generated `*.g.dart` is imported by another file under `lib/`. An allowlist names the four orphans the Known Technical Debt section records as deliberate.
- `test/standards/app_strings_used_test.dart`: every `static const` in `AppStrings` is referenced as `AppStrings.<name>` from a file under `lib/` other than `app_strings.dart`.

The prototype keeps working without its copies: `prototipo-v11/index.html` points its images at `../spec/telas/`, and `docs/design/README.md` points readers to `spec/haptics.md`.

## Alternatives Considered

- Move Settings' theme copy into the `AppStrings` constants instead of deleting them. Rejected: every other Settings row writes its copy inline, so converting four labels would leave the file with two conventions.
- One spec and PR per item. Rejected because each item is a few lines, and one spec keeps the audit's reasoning in one place. Each item still gets its own commit.
- Rewrite the long design studies under `docs/architecture/`, which still discuss TFLite. Rejected: they state that they are research studies, and ADR 0024 is the decision of record. Rewriting them is a separate documentation task.

## Scope

- Includes:
  - deleting `history_grid.dart` and the tests and test cases that pin only it (`history_widgets_test.dart` group `HistoryGrid`, and the `history_grid` cases in `app_motion_wiring_test.dart`, `spacing_tokens_snapped_test.dart` and `ui_copy_accents_test.dart`);
  - deleting the seven unused `AppStrings` constants;
  - removing `cupertino_icons` from `pubspec.yaml` and `pubspec.lock`;
  - the two standards tests above;
  - README and `docs/agents/project.md` corrections, then `mf agents sync`;
  - deleting `docs/superpowers/` and the 13 duplicated prototype files, and repointing `index.html` and `docs/design/README.md`;
  - adding `test/**/failures/` to `.gitignore`.
- Does NOT include:
  - the four deliberate orphans, the CNN path under `ml/`, `docs/reverse-engineering/` (SPEC 0112) or any ADR;
  - `AppSpacing.xxxl`, a token-scale step that is unused today;
  - any UI copy, behaviour or dependency version change;
  - deleting merged remote branches.

## Acceptance Criteria

- `no_library_file_is_orphaned`: fails on `main` because of `history_grid.dart`, and passes after the change.
- `every_app_string_is_used`: fails on `main` for the seven constants, and passes after the change.
- `flutter analyze` reports no issues, and `flutter test` shows no failures beyond the four that `main` already has on this machine (3 palette goldens rendered by Flutter 3.47.7 instead of the pinned 3.44.1, and `harness_wiring_test` run outside the main checkout).
- `rg cupertino_icons` finds no match outside `docs/specs/`.
- `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI; checked locally on Flutter 3.47.7. Run `dart run build_runner build --delete-conflicting-outputs`, `flutter test test/standards`, `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **iOS icon font.** `cupertino_icons` provides only the `CupertinoIcons` font, and the app uses Material and Lucide icons. No CI job exercises a Cupertino icon, so if one is ever added it will need the package back.
- **Guard false positives.** The orphan guard matches the imported file's basename. A future file that is reached only through a `part` or a conditional import would need an allowlist entry that says why.
