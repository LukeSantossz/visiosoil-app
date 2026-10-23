# SPEC: feat(theme): raise confidence thresholds and centralize the badge and bar

## Problem

`ConfidenceLevel` splits high/moderate/low at 80%/60%, and labels the middle
band "Moderada". The redesign (v11 §3.14, decision 14.8) approves different
bands — high >= 75%, moderate 50-74% — and renames the middle label to
"Média". Two screens also each carry their own ad-hoc confidence pill
(`_ConfidenceBadge` in `classification_header.dart`, `_ConfidenceChip` in
`last_analysis_section.dart`), so the badge is not a single source despite
`ConfidenceLevel` itself already being one (§3.14's heading), and no widget
renders the §4 `ConfidenceBar` at all.

## Design Decision

Move the thresholds, rename the label, and add the two §4 components so
`ConfidenceLevel` plus `ConfidenceBadge`/`ConfidenceBar` together are the only
place that renders a confidence score.

- `ConfidenceLevel.highThreshold` 0.75 (was 0.80), `moderateThreshold` 0.50
  (was 0.60). `fromScore` keeps its boundary semantics (`>=` on each
  threshold), so 50% and 75% round up into the band above.
- `ConfidenceLevel.moderate.label` reads "Média" (was "Moderada").
- `ConfidenceLevel.accentColor(palette)`: a new solid semantic accent
  (`primary`/`warning`/`error`), distinct from the existing pastel
  `backgroundColor`/`foregroundColor` container pair, for the bar's fill and
  the advisory banner's border — both drew this ternary inline before.
- `lib/core/widgets/confidence_badge.dart`: `ConfidenceBadge({score, compact})`.
  Renders nothing when `score` is null; otherwise an icon + pill carrying the
  percentage and the level's label — never color alone, §3.14, and the trello
  acceptance criterion holds for `compact` too: it only renders a denser pill
  (smaller icon and horizontal padding), never drops the label. This
  overrides §4's own table, which lists a "compact (só %)" state; the trello
  card's explicit "always label + %" wins per the standards' precedence order.
  The percentage floors rather than rounds (`49%` at `0.499`, `74%` at
  `0.749`), so it can never read a band the score's own threshold hasn't
  reached. A non-finite score drops the percentage and shows only the label,
  matching the home's existing NaN tolerance. Carries the §8 semantics
  convention verbatim: `"Confiança alta, 82 por cento"`.
- `lib/core/widgets/confidence_bar.dart`: `ConfidenceBar({score, animate})`.
  A pill track that fills to `score` in `accentColor`; when `animate`
  (default), the fill tweens from 0 over `AppMotion.reveal` (640ms — the
  closest named token to the mock's 600ms) honoring `AppMotion.durationOf`
  for reduced motion.
- `classification_header.dart` and `last_analysis_section.dart` now build
  `ConfidenceBadge` instead of their own pill; `_ConfidenceBanner`'s accent
  reads `level.accentColor(palette)`.
- The low/moderate advisory banner text changes to the §3.14 approved copy:
  moderate — "Resultado provável. Se puder, refaça a foto para confirmar.";
  low — "O modelo não está seguro. Refaça a foto na sombra, com a amostra
  preenchendo a moldura."

## Alternatives Considered

- **Keep the per-screen pills and only change the thresholds/label.**
  Rejected: the trello card and §3.14's own heading ("fonte única:
  `ConfidenceLevel`") ask for one render path, and the two pills had already
  drifted (12px vs 14px icon, `vertical: 2` vs `AppSpacing.xs` padding).
- **Give `ConfidenceBadge` its own accent-color switch instead of adding
  `ConfidenceLevel.accentColor`.** Rejected: `_ConfidenceBanner` already
  computed the same high/warning/error mapping inline; centralizing it in
  `ConfidenceLevel` serves both the bar and the banner and matches the
  "fonte única" framing.

## Scope

- Includes:
  - `lib/models/confidence_level.dart`: thresholds, label, `accentColor`.
  - `lib/core/widgets/confidence_badge.dart`, `lib/core/widgets/confidence_bar.dart`.
  - `lib/core/features/details/widgets/classification_header.dart`: use
    `ConfidenceBadge`, `level.accentColor`, and the approved banner copy.
  - `lib/core/features/home/widgets/last_analysis_section.dart`: use
    `ConfidenceBadge`.
  - Tests for each criterion, plus the pre-existing accent/spacing source
    guards (`test/ui_copy_accents_test.dart`,
    `test/core/theme/spacing_tokens_snapped_test.dart`) updated to the new
    copy and to the badge's new file.
- Does NOT include:
  - §11 (fractions, top-3, talhão) — untouched.
  - The verdict bands in `classification_verdict.dart`
    (0.15/0.50/0.65) — a different, unrelated scale gating the sheet
    reader's accept/reject/review split, not the confidence badge.
  - The low-confidence banner's "[Fotografar de novo]" retry action from the
    §3.14 table — the trello card asks for the approved *text*, and a retake
    action is the UI/UX terminal's "fuller retake flow" roadmap item (see
    Known Technical Debt), out of this change's scope.
  - Wiring `ConfidenceBar` into any screen — no caller exists yet (the result
    screen's processing/reveal states are PR 8/9 in §12); this spec only adds
    the component per the trello card.
  - `capture_image_preview.dart`'s classification chip: it shows the texture
    class name plus a bare percentage with no level color, which is a
    different thing than `ConfidenceBadge`, not an ad-hoc duplicate of it.

## Acceptance Criteria

- `boundary_49_9_is_low`: `ConfidenceLevel.fromScore(0.499)` is `low`.
- `boundary_50_is_moderate`: `ConfidenceLevel.fromScore(0.50)` is `moderate`.
- `boundary_74_9_is_moderate`: `ConfidenceLevel.fromScore(0.749)` is `moderate`.
- `boundary_75_is_high`: `ConfidenceLevel.fromScore(0.75)` is `high`.
- `moderate_label_is_media`: `ConfidenceLevel.moderate.label == 'Média'`.
- `accent_color_is_solid_and_distinct`: each level's `accentColor` equals the
  named solid token (`primary`/`warning`/`error`), not its container color.
- `badge_shows_label_and_percent`: a non-compact `ConfidenceBadge` renders
  `"<pct>% · <label>"` for all three levels, with the level's icon.
- `badge_compact_shows_label_and_percent_denser`: `compact: true` still
  renders `"<pct>% · <label>"` (same text as non-compact), with a smaller
  icon.
- `badge_percent_floors_at_each_boundary`: `ConfidenceBadge` and its
  semantics label render `49%`/`Baixa` at `0.499`, `74%`/`Média` at `0.749`,
  `50%`/`Média` at `0.50`, and `75%`/`Alta` at `0.75` — the percentage never
  reads a band the score's own threshold hasn't reached.
- `badge_null_score_renders_nothing`.
- `badge_non_finite_score_falls_back_to_label_no_percent`.
- `badge_semantics_match_section_8`: the merged semantics label reads
  `"Confiança alta, 82 por cento"` for a score of 0.82.
- `bar_animates_fill_over_reveal`: with `animate: true` (default), the fill's
  `widthFactor` starts at 0, is strictly between 0 and the score mid-animation,
  and reaches the score after `AppMotion.reveal`.
- `bar_animate_false_renders_final_fill_immediately`.
- `bar_fill_has_track_height`: the fill's rendered size has the track's
  height (not a collapsed zero height) and a width proportional to `score`,
  under both `animate: true` (settled) and `animate: false`.
- `bar_accent_color_matches_palette_token`: the fill's color equals the
  level's exact palette token (`primary`/`warning`/`error`) in both the light
  and dark palette.
- `bar_non_finite_score_renders_empty_fill_without_crashing`.
- `classification_header_banner_uses_approved_copy`: the moderate and low
  banners render the §3.14 texts verbatim; the existing low/moderate/high
  banner-visibility tests continue to pass under the new bands.
- The existing confidence, classification-header and home-widget test suites
  pass with the renamed label and new thresholds.

## Reproducibility

```sh
flutter test test/models/confidence_level_test.dart test/core/widgets/confidence_badge_test.dart test/core/widgets/confidence_bar_test.dart test/features/details/classification_header_test.dart test/features/home/home_widgets_test.dart
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: `AppMotion.reveal` (640ms) is close enough to the mock's 600ms
  that reusing the named token beats introducing a one-off duration; no
  spec text ties the bar to a specific named token.
- Decision, superseding an earlier draft of this spec: the trello card's
  acceptance criterion reads "always label + %", stated without a `compact`
  exception, so it overrides §4's own table entry for the "compact (só %)"
  state rather than refining it — `compact` only denotes a smaller icon and
  tighter padding. Per `code_conventions.md`'s precedence order, the approved
  card's explicit criterion outranks the design doc's table when the two
  disagree.
- Risk: a future screen wiring `ConfidenceBar` chooses a track/fill pairing
  this spec did not anticipate; `accentColor`/`surfaceContainerHigh` are the
  only choices made here and may need revisiting once a caller exists.
- What would invalidate this spec: an approved §3.14 copy revision that
  changes the moderate/low banner text again, or a decision that `compact`
  should hide the icon, which the trello card's criterion does not cover
  either way.
