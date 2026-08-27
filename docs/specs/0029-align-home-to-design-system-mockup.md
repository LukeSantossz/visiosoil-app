# SPEC: feat(home): align the home screen to the design-system mockup

## Problem

The design system ships an authoritative home mockup (`ui_kits/mobile/HomeScreen.jsx`) that the app's home does not match. The DS home is a greeting row + a green hero capture card (primary fill, radius xl, green glow) whose call-to-action is a white "Nova análise" button, followed by the metrics row and a "Última análise" section with a "Ver tudo" link and a record row. The app instead renders a gradient brand-bar hero, a separate dark capture card, the metrics, and a different last-analysis card. The re-audit flagged the home CTA as the last standing brand divergence ("dark card, not the DS green-glow"). The user chose to align the whole home to the DS mockup.

## Design Decisions

Realize `HomeScreen.jsx` faithfully, using the app's existing token layer (`AppColors`/`AppSpacing`/`AppRadius`/`AppTypography`) and reconciling the mockup's off-scale inline values (20 px is not on the DS token scale) to the nearest token per the 0027 convention. The green glow is the DS `--vs-shadow-raised` (`0 4px 12px rgba(74,124,89,.30)`), which the app already tokenizes as `AppColors.shadowBrand`; the white button's shadow is `--vs-shadow-cta` (`0 10px 30px rgba(26,28,25,.20)` = `AppColors.shadowElevated`).

Structure (top to bottom), inside the existing `Scaffold` + `SafeArea` + scroll:

1. **Greeting row** (replaces the brand-bar hero): a small time-of-day line ("Bom dia," / "Boa tarde," / "Boa noite,") over a display-font second line, with a circular person avatar on the right.
   - **Decision — no VisioSoil wordmark on the home.** The DS greeting carries no wordmark; the brand mark (added in 0024/0025) stays on the splash and the launcher icon. Removing it from the home header is the faithful DS layout.
   - **Decision — greeting name is the static audience label "Agrônomo"**, matching the DS mockup, with no auth coupling. Personalizing it with the signed-in Google account name is a deliberate, cheap-to-add follow-up, intentionally out of scope here to keep the home free of auth state.
   - **Decision — settings moves to the avatar.** The person avatar is tappable and routes to `/settings` (the gear it replaces did the same), so settings access is preserved.
2. **Green hero capture card** (replaces the gradient hero and the dark `PrimaryAction` card): `AppColors.primary` fill, `AppRadius.xl` corners, `AppColors.shadowBrand` green glow; contains an uppercase eyebrow ("ANÁLISE INSTANTÂNEA" with an `auto_awesome`/`Icons.auto_awesome` leading icon), the headline "Aponte para o solo e descubra a textura em segundos", and a full-width white capture button ("Nova análise", camera icon, `AppColors.primary` text, `AppColors.shadowElevated` shadow) that navigates to `/capture`. The white button reuses `VisioButton`.
3. **Metrics** — the existing `StatsGrid`, unchanged (already the DS three-up: Análises / Locais / Confiança).
4. **Última análise** — a title-case header row ("Última análise" in the display title style) with a "Ver tudo" text link on the right that switches to the History tab, followed by a record row for the latest classified record.
   - **Decision — "Ver tudo" switches the bottom-nav tab, via a new `mainTabIndexProvider` (a `NotifierProvider<MainTabIndexNotifier, int>`, default 0).** A `NotifierProvider` (not the legacy `StateProvider`, which Riverpod 3 discourages) matches the project's established state pattern — `searchTermProvider`/`selectedTextureFilterProvider` are both `Notifier`-backed. `MainScreen` becomes a `ConsumerWidget` reading it to drive the `IndexedStack` index, the `NavigationBar` selection, and the existing back-to-home `PopScope`; the home's "Ver tudo" calls `select(1)`. History has no pushable route today (it is a tab), so a shared index is the idiomatic way to reach it from home content.
   - **Decision — the record row uses the real photo thumbnail** (48×48, `AppRadius.md`) rather than the mockup's flat color swatch (the mockup has no real images; the app does), plus the texture class, a "location · when" line, a confidence indicator derived from `ConfidenceLevel`, and a trailing chevron; tapping it opens `/details`.

Behavior preserved from today: the single inline error card (`HomeDataError`) still replaces the metrics + last-analysis region when the records stream errors (hero/CTA stay usable); the last-analysis section renders nothing when there is no classified record; `StatsGrid` still shows `-` until stats resolve.

## Alternatives Considered

- **Glow-only (swap the dark card's shadow to the green glow):** rejected by the user in favor of full DS alignment; a green halo behind a near-black card does not match the DS's green hero card.
- **Personalize the greeting with the Google account name:** deferred — it couples the home to auth async state for marginal benefit; the DS uses a static label.
- **Keep the VisioSoil wordmark in the header:** rejected — the DS greeting has none, and keeping it would be a self-imposed divergence from the very mockup this change aligns to.
- **A pushable `/history` route for "Ver tudo":** rejected — History is a bottom-nav tab; a second entry point via a route would double-render it and lose tab state. A shared index provider is cleaner.

## Scope

- Includes:
  - Rewrite `home_screen.dart` composition and its `home/widgets/` (greeting + avatar, green hero capture card, last-analysis header + "Ver tudo" + record row). `hero_section.dart` and `primary_action.dart` are replaced by the greeting + hero-card widgets; `last_analysis_section.dart` is restructured.
  - `main_screen.dart` → `ConsumerWidget` driven by a new `mainTabIndexProvider` (new provider file under `lib/providers/`), preserving the current tab set, labels, and back-to-home behavior.
  - New pt-BR copy ("Análise instantânea" eyebrow, the headline, "Ver tudo", the greeting) kept inline in each widget, matching the project's established pattern: `app_strings.dart` holds only cross-layer shared strings, and #38 deliberately declined centralizing UI copy (throwaway before a `flutter_localizations`/`.arb` consumer exists).
  - Token-scale spacing/radius throughout (no off-scale literals), consistent with 0027.
- Does NOT include:
  - The History screen/grid, Settings screen, capture/details/preview screens — unchanged (only the entry points into them change).
  - Auth-based greeting personalization.
  - Any change to `StatsGrid`'s data or the providers feeding stats/latest/records.
  - Bottom navigation destinations, icons, or count.
  - Dark-mode/theming changes beyond the hero card's own colors.

## Acceptance Criteria

- greeting_rendered: the home shows the time-of-day greeting line, the "Agrônomo" display line, and a tappable person avatar that routes to `/settings`; no VisioSoil wordmark appears on the home.
- hero_cta: the capture CTA is a single green (`AppColors.primary`) card with `AppRadius.xl` corners and the `AppColors.shadowBrand` green glow, containing the eyebrow, the headline, and a full-width white "Nova análise" button (text in `AppColors.primary`) that navigates to `/capture`.
- see_all_switches_tab: tapping "Ver tudo" selects the History tab via `mainTabIndexProvider` (asserted by a widget test on `MainScreen` + the home, and by the provider state), with the back button still returning to Home.
- last_analysis_row: when a classified record exists, the section renders a row with its thumbnail, texture class, location·timestamp, a confidence indicator, and a chevron, and tapping it pushes `/details`; when none exists, the section renders nothing.
- error_and_empty_preserved: a records-stream error still shows the inline `HomeDataError` in place of the metrics + last-analysis region while the greeting and CTA remain; existing home tests for these paths stay green.
- tokens_only: the new/edited home and main files contain no off-scale spacing/radius literals; they reference `AppSpacing`/`AppRadius`/`AppColors`/`AppTypography`.
- analyze_clean_tests_green: `flutter analyze` reports no issues; `flutter test` passes.
- visual_inspection: the home is inspected on the Android emulator and matches the DS mockup (green hero CTA with glow, greeting, metrics, last-analysis with "Ver tudo").

## Reproducibility

- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Design source: `VisioSoil Design System/ui_kits/mobile/HomeScreen.jsx` and `tokens/spacing.css` (shadow tokens `--vs-shadow-raised` / `--vs-shadow-cta`), mirrored by `AppColors.shadowBrand` / `AppColors.shadowElevated`.
- Verify: `flutter analyze && flutter test`, then inspect the home on an emulator.

## Risks and Assumptions

- Assumption: making `MainScreen` read a `mainTabIndexProvider` preserves the current tab and back-button behavior; verified by keeping the `PopScope` semantics (non-zero index pops back to Home) driven by the provider, with a test.
- Assumption: `VisioButton` can render a white-on-primary variant for the hero button via its existing API or a thin style hook; if it cannot without an out-of-scope change, the hero button falls back to a self-contained button matching the DS style, noted in the PR.
- Assumption: removing the wordmark from the home is acceptable given it remains on the splash/launcher; flagged for the Gate.
- Risk: this is a broad visual change; each section is validated on the emulator against the mockup before merge and is reversible section-by-section.
