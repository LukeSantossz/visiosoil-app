# SPEC: feat(splash): add the boot sieve animation and a logo hero into Home

## Problem

The boot screen is still SPEC 0089's static tile-and-fade splash, matched pixel for pixel to the native Android launch window; redesign v11's boot "Peneira" (§3.1, §6.2, PR 14) is a different screen entirely — a full-screen green entrance with a sieve mesh and falling grains behind the bare logo mark, "Pular" to skip, and a `Hero` flight of the logo into Home — and nothing in the repo builds it yet.

## Design Decision

Rewrite `splash_screen.dart` as the boot "Peneira": a `Scaffold` on `AppPalette.bootBackground` (new getter: light's `primary`, dark's `onPrimary`, Sol's `primary` — §1.1's three boot hex values), with a single `AnimationController` (duration = the 1.2 s hand-off mark) driving three `Interval`-gated stages read by `AnimatedBuilder`s: the mesh's fade + scale .96→1 (0–250 ms, `emphasizedDecelerate`), a `CustomPainter` of pre-generated (`Random(42)`) grains falling and settling with a 20 ms stagger (760 ms each, `emphasizedDecelerate`), and the logo + name rising 8 px with a fade (250–500 ms, `standardDecelerate`). "Pular" stops the controller and routes at once. The controller's own `AnimationStatus.completed` triggers the hand-off, so the 1.2 s mark in §6.2 and the duration are the same number, not two values that can drift.

The onboarding-completion read that decides `/` vs `/onboarding` is kicked off in `initState` rather than awaited after the entrance, so routing adds no wait of its own on top of the 1.2 s controller — the old splash's extra 500 ms "smooth transition" delay is dropped, since it is what would have pushed the total past the ≤1.6 s budget this PR's acceptance criterion sets.

**Reduced motion** (`AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context)`, read once in `didChangeDependencies`) swaps the whole entrance for just the logo, a 150 ms linear fade, no mesh, no grains, no `CustomPainter` — not a shortened version of the full entrance, a different, smaller tree. "Pular" and the background stay, since they are controls and a fill, not motion.

**The Hero.** `visioSoilLogoHeroTag` is a top-level constant beside `VisioSoilLogo` (neither splash nor home owns the other) that both ends wrap their logo in. Home has no app-bar logo to land on today — `HomeGreeting` is explicitly tested to carry none (`find.byType(VisioSoilLogo), findsNothing`, SPEC 0029: "the brand mark... stays on the splash and launcher") — so a small 32 dp badge is added to `home_screen.dart` itself, above `HomeGreeting`, rather than inside it: the Hero flight gets a real landing target without reopening SPEC 0029's decision that the greeting row carries no wordmark.

## Alternatives Considered

- **Keep the native-launch-window tile match (SPEC 0089) and layer the new mesh/grains around the still tile.** Rejected: the reference screenshot (`telas/01-boot-peneira.png`) shows the bare mark directly on green, no rounded gradient tile, and §6.2 step 3 explicitly has the logo itself rise and fade — SPEC 0089's whole premise was that the tile never moves. Keeping both would mean animating a tile the design no longer shows.
- **Derive `bootBackground` from `isSun` plus a light/dark branch.** Rejected for a plainer one: dark's boot colour (`#1B3625`) is already the dark palette's `onPrimary` value, and Sol's (`#1F4D2E`) is already Sol's `primary` — `brightness == dark ? onPrimary : primary` reads all three correct values off the existing palettes with no new stored colour and no `isSun` branch.
- **Drive navigation with a plain `Future.delayed(1200ms)` timer, as the old splash did.** Rejected: tying the hand-off to `AnimationController.status` instead means the 1.2 s in the controller's `duration` and the 1.2 s in §6.2's "Hero do logo" are read from one place, so a future change to the entrance's timing cannot silently desync the two.
- **Widgets, not a painter, for the falling grains (`AnimatedPositioned` per grain, or a `Stack` of `Positioned` circles).** Rejected per this PR's own requirement and the precedent `capture_guide_overlay.dart`/§6.3 set: one `CustomPainter` reading `controller.value` through `Interval`s, grains as plain pre-generated data, wrapped in `RepaintBoundary` — no widget per grain.
- **Put the Home landing badge inside `HomeGreeting`.** Rejected: that widget has a passing test asserting it shows no wordmark (SPEC 0029), written on purpose when the brand mark moved to the splash alone. Changing that call without a deliberate Home-header decision would be scope creep on a boot-screen PR; the badge instead lives in `home_screen.dart`, a sibling of `HomeGreeting`, so neither SPEC 0029's decision nor its test needs to change.

## Scope

- Includes:
  - `lib/core/features/splash/splash_screen.dart`: the full rewrite above.
  - `lib/core/theme/app_palette.dart`: `AppPalette.bootBackground`.
  - `lib/core/widgets/visio_soil_logo.dart`: the shared `visioSoilLogoHeroTag` constant.
  - `lib/core/features/home/home_screen.dart`: the 32 dp Hero badge above `HomeGreeting`.
  - `test/features/splash/splash_screen_test.dart`: rewritten for the new screen (the criteria below).
  - `test/features/home/home_screen_test.dart`: one test for the landing target.
  - `test/core/theme/spacing_tokens_snapped_test.dart`: the splash block, updated to the new source (its tile-radius/brand-shadow assertions no longer apply).
  - `SplashScreen.logoTileSize`/`logoMarkSize`/`logoTileRadius`: kept as the native launch window's geometry, so `test/android_launch_screen_test.dart` keeps pinning the Android drawables (SPEC 0089) unchanged.
- Does NOT include:
  - Deleting `test/android_launch_screen_test.dart` or editing `docs/specs/0089-*.md`; both stay intact.
  - Updating the Android (`launch_background.xml`, `launch_tile.xml`, `launch_mark.xml`, `launch_icon.xml`, `styles.xml`) or iOS (`LaunchScreen.storyboard`) native launch resources to the new green boot design. They are left exactly as SPEC 0089 wrote them — unchanged, and now unmatched to the first Flutter frame (see Risks and Assumptions). A native-side follow-up is a separate PR.
  - Redesigning Home's header to the newer `telas/08-home.png` mockup (a plain "Início" title, no greeting, no avatar) — that mockup is ahead of what PR 6 shipped and is that PR's own follow-up, not this one's. The 32 dp badge added here is deliberately minimal and additive, not a step toward that layout.
  - Any change to `AppMotion` tokens, `AppHaptics`, or the confidence/contrast work other PRs in this sequence cover.
  - The onboarding routing decision itself (`OnboardingStore.hasCompletedOnboarding`) — only when it is read changes, not what it returns or how it is computed.

## Acceptance Criteria

- `boot_navigates_home_within_the_1_6s_budget`: from first frame, the boot has left for `/` (or `/onboarding`) within 1.6 s of pumped time.
- `first_launch_routes_to_onboarding_instead_of_home`: with no completed onboarding, the same entrance routes to `/onboarding` instead, on the same timeline.
- `pular_navigates_immediately_without_waiting_for_the_entrance`: tapping "Pular" right after the first frame leaves the boot well before the 1.2 s mark.
- `pular_causes_no_double_navigation_once_the_entrance_would_end`: after "Pular", advancing the clock past the entrance's own 1.2 s mark throws nothing and does not navigate a second time.
- `the_logo_carries_the_shared_hero_tag_during_the_entrance` / `home carries the boot logo hero landing target`: a `Hero` with `visioSoilLogoHeroTag` wrapping a `VisioSoilLogo` exists on the boot's first frame and inside `HomeScreen`.
- `reduce_motion_shows_only_the_logo_with_a_150ms_fade_and_no_painter`: with reduced motion, no widget paints with the sieve/grains painter, "VisioSoil" and the tagline are absent, "Pular" is still present and tappable, and the logo's `FadeTransition` runs over 150 ms.
- `full_motion_renders_the_sieve_mesh_and_grains_painter`: without reduced motion, the sieve/grains painter is present partway through the entrance.
- `boot_never_vibrates_through_a_full_entrance_and_hand_off` / `boot_never_vibrates_when_skipped`: no `HapticFeedback` platform call occurs, entrance or "Pular".
- `boot_background_matches_each_theme`: the `Scaffold`'s background is `AppPalette.light.primary` (light), `AppPalette.dark.onPrimary` (dark), and `AppPalette.sun.primary` (Sol).
- The boot passes Flutter's four accessibility guidelines (SPEC 0133) in light and dark, with the entrance's fade settled.
- The existing `splash_permissions_test.dart` (no permission requested from boot) passes unchanged.

## Reproducibility

```sh
flutter test test/features/splash/ test/features/home/ test/core/theme/spacing_tokens_snapped_test.dart test/core/theme/app_palette_test.dart
flutter analyze && flutter test && mf check
```

Grain seed `42`, `grainCount = 20`. Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumption: leaving the native Android launch resources unchanged (Scope) is acceptable even though it reopens the seam SPEC 0089 removed — the native window still shows the old gradient tile on the app background for a frame before Flutter's first frame now shows a plain green fill with a bare mark. SPEC 0089's own device check found the hand-over already imperfect on API 34 (a 30 px jump, logged in its Risks), so this is a regression in degree on top of one that already existed, not a newly introduced seam on an otherwise seamless launch. If this reads as the wrong call, the question is: **should this PR also rewrite the native launch drawables to the new green boot, or is that deferred to its own PR** (it touches `res/values*/colors.xml`, two `styles.xml` variants, and four drawables, none of which this PR's acceptance criteria exercise)? This spec takes the deferred option.
- Assumption: a 32 dp badge in `home_screen.dart`, outside `HomeGreeting`, is an acceptable landing target given neither the currently-implemented Home header nor the newer `telas/08-home.png` mockup shows a persistent logo there. The alternative — not adding one, and leaving the Hero a no-op until Home's own PR adds a target — was rejected because this PR's own acceptance criteria (and the task that asked for it) call for a working Hero flight today, not a tag prepared for later use.
- Assumption: `AnimationController`'s default `AnimationBehavior.normal` already shortens the full-motion entrance to near-zero when the platform's `disableAnimations` is on (SPEC 0120), so folding that signal into the same `_reduceMotion` check that also swaps the widget tree (rather than relying on the framework's scaling alone, as SPEC 0120 left the other three pre-existing sites) is what makes "no painter" true for both reduced-motion signals, not just the stored preference.
- What would invalidate this spec: a field or device report that the native-to-Flutter hand-off reads as a visible flash or colour jump severe enough to need fixing before this ships, which would mean the native launch resources cannot stay deferred.
