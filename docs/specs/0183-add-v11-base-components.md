# SPEC: feat(widgets): add the redesign v11 base component library

## Problem

Redesign v11's tokens (§1–§2, PR 1, SPEC 0178) and motion/haptics (PR 2, SPEC 0179) exist, but the screens still render their own ad-hoc widgets — `stats_grid.dart`'s private `_StatCard`, a two-variant `VisioButton` without a plain text style or an alternate loading label — and v11 §4's catalogue of six named components (`AnalysisTile`, `SegmentedControl`, `SettingsSwitchTile`, `StatCell`/`StatsRow`, `StatusPill`, `SwipeToDelete`) has no implementation at all. Every screen PR after this one (history's list, the sync status surfaces, Settings' toggles) needs these to already exist, built against the tokens rather than against literal values, so that screen migration is a wiring change and not a design decision repeated six times.

## Design Decision

Add the six v11 §4 components as standalone widgets under `lib/core/widgets/`, each consuming `AppPalette`/`AppSpacing`/`AppRadius`/`AppMotion`/`AppHaptics` rather than literal colors or durations, and wire the one for which a caller already exists today.

**`StatCell` / `StatsRow`** (`lib/core/widgets/stat_cell.dart`): `StatCell` is `stats_grid.dart`'s former private `_StatCard` promoted to a shared widget — same card chrome (shadow, border, radius), same bold value over a label, with an optional leading icon — plus a `StatCell.skeleton` constructor (a shimmering placeholder over `AppMotion`'s 1.2 s loop, off under reduced motion, mirroring SPEC 0179's reduced-motion rule) and a `semanticLabel` override for a reading that isn't just `"<value> <label>"` (v11 §8). `StatsRow` lays a list of cells out at equal width with `AppSpacing.sm` between them. `StatsGrid` (`lib/core/features/home/widgets/stats_grid.dart`) is rewired to build three `StatCell`s inside a `StatsRow` instead of its own `_StatCard`/`Row`/`SizedBox` — the only one of the six with a production caller in this PR.

**`AnalysisTile`** (`lib/core/widgets/analysis_tile.dart`): a record row — thumbnail (texture-colored border, or the outline color when the record failed classification), texture class or, when `record.classificationFailure` is set, "Não classificada" plus the failure's own copy from `classificationFailureChip` (ADR 0015), place/time, and a trailing compact `ConfidenceBadge`, `StatusPill.pending` when the record is still unsynced, a chevron, or an error icon on failure. An `onDelete` callback adds an "Excluir" custom semantics action — the non-gesture equivalent of a `SwipeToDelete` wrapping the tile, for a screen-reader or switch-control user (v11 §8). `dense` shrinks the thumbnail (56→48 dp) and padding. `AnalysisTileSkeleton` is its loading placeholder. No caller yet — history's screen still renders a thumbnail grid (v11 PR 10 migrates it to this tile).

**`SegmentedControl<T>`** (`lib/core/widgets/segmented_control.dart`): a pill-shaped control whose selection indicator slides to the active option over `AppMotion.base`. The border is a `foregroundDecoration` rather than the clip-shape `decoration`'s own border, so it doesn't reserve padding that would shrink a segment below the 48 dp floor (v11 §8). Height reads `context.density.tap` — the second production reader of `AppDensity` after `_SettingsTile` (SPEC 0182) — so it grows to 56 dp under Modo Sol with no separate code path. Plays `AppHaptics.selection` only when the tap actually changes the selection (v11 §7), not on a re-tap of the already-selected segment. No caller yet.

**`SettingsSwitchTile`** (`lib/core/widgets/settings_switch_tile.dart`): a settings row — optional leading icon, title, optional subtitle, trailing animated switch — where tapping anywhere in the row toggles the value, not just the switch itself. The switch's track color, thumb position and thumb size tween over `AppMotion.base` with the emphasized curve, approximating the mock's spring (v11 §4: "mola do thumb"). Plays `AppHaptics.selection` on toggle by default; a caller whose own toggle samples a different tier (e.g. turning Vibração itself on, which plays `AppHaptics.confirm`) passes `haptic: false` and fires its own haptic after committing the preference, rather than this tile's default firing first. `onChanged: null` disables and visibly dims the tile (38% opacity on the switch) and drops its `Semantics.onTap`. No caller yet.

**`StatusPill`** (`lib/core/widgets/status_pill.dart`): an icon+label pill for `StatusPillStatus.sent`/`pending`/`error`, each with its own container/foreground color pair from `AppPalette` — color is never the only signal, the icon and label differ too. Decoupled from `SoilRecord.syncStatus`'s raw string by design: a caller maps its own status to this enum rather than the widget knowing the sync model. `AnalysisTile`'s trailing pending state is its first caller.

**`SwipeToDelete`** (`lib/core/widgets/swipe_to_delete.dart`): wraps a child in a horizontal drag that reveals a red "Excluir" action past a configurable `threshold` (50 dp default), collapsing the row over `AppMotion.base` with an `AnimatedSize` once deleted and showing a snackbar with an optional "Desfazer" (`onUndo`) action. Restoring the underlying data on undo is the caller's job — this widget only asks for it. An "Excluir" custom semantics action mirrors the gesture for a screen-reader or switch-control user, who cannot drag a list row (v11 §8). No caller yet — history's screen still renders a thumbnail grid (v11 PR 10 wires this in, alongside `AnalysisTile`).

**`VisioButton`** (`lib/core/widgets/visio_button.dart`), extended rather than replaced: `VisioButtonVariant` gains `text` — a plain, neutral-colored `TextButton`, distinct from `destructive`'s error-colored one (v11 §4: primary/outlined/text/destructive) — and a new `loadingLabel` parameter shows a 16 dp spinner next to an alternate label (e.g. "Salvando...") while `isLoading`, instead of the spinner alone (v11 §4: "spinner + label alternativo"). `loadingLabel: null` keeps the pre-existing spinner-only behavior and its 20×20 dp sizing (SPEC 0123) exactly as before.

**`ConfidenceBadge`**'s private `_floorPercent` is renamed to the top-level `floorConfidencePercent` and exported, so `AnalysisTile`'s semantics label states the same percentage for the same score as the badge itself, computed once rather than reimplemented.

**`classificationFailureChip`** moves from `lib/core/features/capture/widgets/classification_failure_chip.dart` to `lib/core/services/classification_failure_copy.dart` (and its test from `test/features/capture/` to `test/services/`), unchanged in content. It is a pure function of `ClassificationFailureCause` with no widget dependency, and `AnalysisTile` — in `core/widgets/`, not `core/features/capture/` — now needs its copy too; a `widgets/` importing a sibling feature's `widgets/` file would be the wrong direction, so the function moves to `services/` where both callers can reach it without one depending on the other's feature folder.

## Alternatives Considered

- **Leave `classificationFailureChip` where it was and let `AnalysisTile` import `core/features/capture/widgets/classification_failure_chip.dart`.** Rejected: a shared pure function living inside one feature's widget folder, imported by a different feature and by `core/widgets/`, inverts the dependency direction `CLAUDE.md`'s Code Organization describes (`core/widgets/` as the shared layer beneath features) and would only get worse once history's screen (v11 PR 10) adopts `AnalysisTile` too.
- **Give `AnalysisTile` its own private copy of the failure-cause copy.** Rejected: ADR 0015 already settled one copy string per cause, and duplicating the switch would let the chip and the tile's "Não classificada" subtitle drift on the next cause added to the enum.
- **Keep `_StatCard` private to `stats_grid.dart` and write a separate `StatCell` for v11 §4.** Rejected: the two would be pixel-identical on day one and diverge silently afterward; promoting the existing card is the only way `stats_grid`'s own snapshot test (`spacing_tokens_snapped_test.dart`) keeps meaning what it already asserts.
- **Make `SegmentedControl` read a fixed 48 dp height instead of `context.density.tap`.** Rejected: v11 §8's 56 dp Sol tap target applies to every interactive control, not only Settings' rows that SPEC 0182 already covers, and reading the token now means Sol adoption needs no further change to this widget.

## Scope

- Includes:
  - `lib/core/widgets/stat_cell.dart`: `StatCell`, `StatCell.skeleton`, `StatsRow`.
  - `lib/core/widgets/analysis_tile.dart`: `AnalysisTile`, `AnalysisTileSkeleton`.
  - `lib/core/widgets/segmented_control.dart`: `SegmentedControl<T>`, `SegmentedControlOption<T>`.
  - `lib/core/widgets/settings_switch_tile.dart`: `SettingsSwitchTile`.
  - `lib/core/widgets/status_pill.dart`: `StatusPill`, `StatusPillStatus`.
  - `lib/core/widgets/swipe_to_delete.dart`: `SwipeToDelete`.
  - `lib/core/widgets/visio_button.dart`: `VisioButtonVariant.text`, `loadingLabel`.
  - `lib/core/widgets/confidence_badge.dart`: `_floorPercent` → public `floorConfidencePercent`.
  - `lib/core/services/classification_failure_copy.dart`: `classificationFailureChip`, moved from `core/features/capture/widgets/classification_failure_chip.dart` (deleted), with every importer (`capture_image_preview.dart`, `management_tips_section.dart`, `classification_header.dart`, `capture_protocol_doc_test.dart`) repointed.
  - `lib/core/features/home/widgets/stats_grid.dart`: rewired onto `StatCell`/`StatsRow`, `_StatCard` removed.
  - `test/core/widgets/{analysis_tile,segmented_control,settings_switch_tile,stat_cell,status_pill,swipe_to_delete}_test.dart`, `test/services/classification_failure_copy_test.dart` (moved from `test/features/capture/classification_failure_chip_test.dart`).
  - `test/core/theme/spacing_tokens_snapped_test.dart`: the card-padding assertion follows `_StatCard`'s content to `stat_cell.dart`.
  - `test/core/widgets/visio_button_test.dart`: coverage for `text` and `loadingLabel`.
- Does NOT include:
  - Wiring `AnalysisTile`, `SegmentedControl`, `SettingsSwitchTile`, or `SwipeToDelete` into any screen — history's thumbnail grid, Settings' existing rows, and any future segmented view are each a later PR's scope (v11 PR 10 for the history migration).
  - Retiring `_SettingsTile` (SPEC 0182) in favor of `SettingsSwitchTile` — the two are not yet the same row (one has no switch), and Settings' screen is untouched here.
  - `AppDensity` reaching any control beyond `_SettingsTile` (SPEC 0182) and `SegmentedControl`'s height in this PR.
  - A list row's 64 dp Sol height from §1.3 (a dedicated list-row component) — `AnalysisTile`'s `minHeight: 56` is the same generic tap target SPEC 0182 applied elsewhere, not that larger figure.
  - Any change to `ClassificationFailureCause`'s causes, copy strings, or retry semantics — only the function's file moved.

## Acceptance Criteria

- `stat_cell_renders_value_label_and_optional_icon` / `stat_cell_semantic_label_combines_value_and_label_or_uses_the_override`: `StatCell` shows value/label/icon and exposes `semanticLabel ?? "$value $label"`.
- `stat_cell_skeleton_shows_no_text_and_is_excluded_from_semantics` / `stat_cell_skeleton_does_not_animate_under_reduced_motion`: the skeleton renders no value/label and stops animating under `AppMotion.reduceMotion`/`MediaQuery.disableAnimationsOf`.
- `stats_row_lays_cells_out_at_equal_width`: `StatsRow` gives each `StatCell` the same width.
- `stats_grid_still_shows_three_cells_built_from_stat_cell`: `StatsGrid` renders through `StatCell`/`StatsRow` and the home screen's existing stats assertions still pass.
- `stat_cell_meets_the_text_contrast_guideline`: `StatCell` passes `meetsGuideline(textContrastGuideline)`.
- `analysis_tile_normal_state_shows_class_time_and_a_compact_confidence_badge`; `analysis_tile_pending_state_shows_the_status_pill_instead_of_the_chevron`; `analysis_tile_error_state_shows_the_failure_reason_not_a_fabricated_class`.
- `analysis_tile_semantics_label_follows_§8`: class/time/percentage for a classified record, the failure's own chip label for a failed one, with ", pendente de sincronização" appended when unsynced.
- `analysis_tile_a_non_finite_confidence_score_does_not_crash_and_drops_the_percent`: mirrors `ConfidenceBadge`'s own guard, through the shared `floorConfidencePercent`.
- `analysis_tile_ondelete_adds_an_excluir_custom_semantics_action_only_when_given`.
- `analysis_tile_dense_shrinks_the_thumbnail`; `analysis_tile_skeleton_renders_no_text_and_is_excluded_from_semantics`.
- `analysis_tile_meets_the_accessibility_guidelines_in_both_themes`.
- `segmented_control_shows_every_option_and_calls_onchanged_only_when_the_tapped_option_differs_from_the_current_value`.
- `segmented_control_plays_the_selection_haptic_only_when_the_value_changes`.
- `segmented_control_indicator_slides_to_the_selected_option_over_appmotion_base`.
- `segmented_control_each_option_exposes_button_and_selected_semantics`; `segmented_control_meets_the_accessibility_guidelines_in_both_themes`.
- `settings_switch_tile_shows_title_and_subtitle_and_tapping_the_row_toggles_the_value`.
- `settings_switch_tile_a_null_onchanged_disables_the_tile`.
- `settings_switch_tile_plays_the_selection_haptic_by_default_and_haptic_false_silences_it`.
- `settings_switch_tile_exposes_toggled_and_enabled_semantics_merging_title_and_subtitle_into_one_label`.
- `settings_switch_tile_meets_the_accessibility_guidelines_in_both_themes`.
- `status_pill_shows_the_right_label_and_icon_for_each_of_the_three_statuses_with_three_distinct_colors`.
- `status_pill_exposes_the_status_as_its_semantics_label`; `status_pill_meets_the_text_contrast_guideline_in_both_themes`.
- `swipe_to_delete_closed_shows_only_the_child`; `swipe_to_delete_dragging_past_the_threshold_reveals_excluir`.
- `swipe_to_delete_tapping_excluir_collapses_the_row_calls_ondelete_and_shows_a_snackbar_with_desfazer_only_when_onundo_is_given`.
- `swipe_to_delete_threshold_is_configurable`; `swipe_to_delete_exposes_an_excluir_custom_semantics_action`.
- `visiobutton_text_variant_renders_a_textbutton_with_the_default_foreground_not_the_error_color`.
- `visiobutton_loadinglabel_shows_the_spinner_next_to_the_alternate_label_and_hides_the_normal_label`.
- `visiobutton_without_loadinglabel_the_spinner_alone_keeps_its_pre_existing_20x20_size`.
- `classification_failure_copy_every_cause_still_has_a_chip_label_and_the_same_retryable_set`: the moved function and its test assert exactly what `classification_failure_chip_test.dart` asserted before the move.
- Every file that imported `core/features/capture/widgets/classification_failure_chip.dart` compiles against `core/services/classification_failure_copy.dart` instead, and `flutter analyze` reports no remaining reference to the deleted path.

## Reproducibility

```sh
flutter test test/core/widgets/analysis_tile_test.dart test/core/widgets/segmented_control_test.dart test/core/widgets/settings_switch_tile_test.dart test/core/widgets/stat_cell_test.dart test/core/widgets/status_pill_test.dart test/core/widgets/swipe_to_delete_test.dart test/core/widgets/visio_button_test.dart test/services/classification_failure_copy_test.dart test/core/theme/spacing_tokens_snapped_test.dart test/standards/capture_protocol_doc_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: moving `classificationFailureChip` to `core/services/` rather than, say, `core/constants/` is the right home for a pure function with no state — `services/` already holds other stateless pure helpers read across features (`share_content_builder.dart`), so this follows that precedent rather than setting a new one.
- Risk: five of the six components (`AnalysisTile`, `SegmentedControl`, `SettingsSwitchTile`, `StatusPill`'s standalone use, `SwipeToDelete`) ship with no production caller, so nothing in the app today exercises them outside their own widget tests; a change to a shared token (`AppPalette`, `AppMotion`) could silently break one of them without any screen-level test noticing until the PR that finally wires it in.
- Risk: `SwipeToDelete`'s drag-to-delete gesture has no keyboard/switch-control equivalent test beyond asserting the custom semantics action exists — whether a real screen reader actually surfaces and fires that action the way this spec assumes is untested here.
- What would invalidate this spec: the screen PR that wires `AnalysisTile` or `SwipeToDelete` into history (v11 PR 10) discovering that either widget's API (e.g. `AnalysisTile`'s `dense` flag, `SwipeToDelete`'s fixed 104 dp action width) doesn't fit the real list's layout, forcing a shape change here after the fact.

## Reference

Trello card: https://trello.com/c/AJKPzmyo
