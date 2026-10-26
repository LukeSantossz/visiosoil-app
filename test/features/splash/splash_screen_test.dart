import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/splash/splash_screen.dart';
import 'package:visiosoil_app/core/services/onboarding_store.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

import '../../support/guidelines.dart';
import '../../support/haptics_recorder.dart';

/// Guards the boot "Peneira" redesign (v11 §3.1, §6.2, §7, PR 14, SPEC 0193):
/// the ≤1.6 s entrance, "Pular", reduced motion, the Hero hand-off to Home,
/// and that boot never vibrates.
void main() {
  GoRouter router(bool completed) => GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: visioSoilLogoHeroTag,
                  child: VisioSoilLogo(size: 32, color: Colors.black),
                ),
                Text('HOME_STUB'),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const Scaffold(body: Text('ONBOARDING_STUB')),
      ),
    ],
  );

  Future<void> pumpSplash(
    WidgetTester tester, {
    bool completed = true,
    ThemeData? theme,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(_FakeStore(completed)),
        ],
        child: MaterialApp.router(
          theme: theme,
          routerConfig: router(completed),
        ),
      ),
    );
  }

  // Mirrors the splash's own timeline: unmounting first makes any pending
  // callback stop at its `mounted` check, then advancing the clock lets a
  // disposed controller's ticker finish, so no timer outlives the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  bool hasBootPainter(WidgetTester tester) => find
      .byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString() == '_BootSievePainter',
      )
      .evaluate()
      .isNotEmpty;

  Finder heroLogo() => find.byWidgetPredicate(
    (w) =>
        w is Hero && w.tag == visioSoilLogoHeroTag && w.child is VisioSoilLogo,
  );

  // SplashScreen.heroDelay is the controller's own duration, so the
  // entrance commits to navigating at exactly this mark — comfortably inside
  // the ≤1.6 s budget. (The route's own push/Hero transition runs after this,
  // the same chrome every navigation in the app pays — see `_settle` in
  // `home_navigation_test.dart` for the precedent of not bounding that part.)
  test('the_entrance_commits_to_navigating_well_within_the_1_6s_budget', () {
    expect(
      SplashScreen.heroDelay,
      lessThanOrEqualTo(const Duration(milliseconds: 1600)),
    );
  });

  // PNG 01 as SPEC 0207 measures it.
  testWidgets('boot_text_matches_the_mock', (tester) async {
    for (final (_, theme) in appThemes) {
      await pumpSplash(tester, theme: theme);

      final title = tester.widget<Text>(find.text('VisioSoil'));
      expect(title.style?.fontFamily, 'InterVariable');
      expect(title.style?.fontSize, 32);
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(
        tester.widget<Text>(find.text('Análise de textura do solo')).style
            ?.fontSize,
        16,
      );
      final skip = tester.widget<Text>(find.text('Pular'));
      expect(skip.style?.fontSize, 17);
      expect(skip.style?.fontWeight, FontWeight.w600);

      await unmount(tester);
    }
  });

  testWidgets('boot_draws_contours', (tester) async {
    for (final (name, theme, drawn) in [
      ('light', AppTheme.light, true),
      ('sun', AppTheme.sun, false),
    ]) {
      await pumpSplash(tester, theme: theme);

      expect(
        find.byKey(const Key('boot-contours')),
        drawn ? findsOneWidget : findsNothing,
        reason: name,
      );

      await unmount(tester);
    }
  });

  testWidgets('boot_navigates_home_within_the_1_6s_budget', (tester) async {
    await pumpSplash(tester);

    await tester.pump(SplashScreen.heroDelay);
    await tester.pumpAndSettle();

    expect(find.text('HOME_STUB'), findsOneWidget);
    expect(find.text('ONBOARDING_STUB'), findsNothing);
  });

  testWidgets('first_launch_routes_to_onboarding_instead_of_home', (
    tester,
  ) async {
    await pumpSplash(tester, completed: false);

    await tester.pump(SplashScreen.heroDelay);
    await tester.pumpAndSettle();

    expect(find.text('ONBOARDING_STUB'), findsOneWidget);
  });

  testWidgets('pular_navigates_immediately_without_waiting_for_the_entrance', (
    tester,
  ) async {
    await pumpSplash(tester);

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('pular_causes_no_double_navigation_once_the_entrance_would_end', (
    tester,
  ) async {
    await pumpSplash(tester);

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The entrance's own 1.2 s mark, had Pular not already left: must not
    // throw or navigate a second time (the splash is gone, undisposed timer
    // would also fail the test on its own).
    await tester.pump(SplashScreen.heroDelay);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the_logo_carries_the_shared_hero_tag_during_the_entrance', (
    tester,
  ) async {
    await pumpSplash(tester);

    expect(heroLogo(), findsOneWidget);

    await unmount(tester);
  });

  testWidgets(
    'reduce_motion_shows_only_the_logo_with_a_150ms_fade_and_no_painter',
    (tester) async {
      // The stored "Reduzir movimento" preference, not the platform's own
      // `disableAnimations` signal: that signal makes the framework additionally
      // scale any normal `AnimationController` to ~5 % of its duration (SPEC
      // 0120), which would make the 150 ms this test measures unobservable.
      AppMotion.reduceMotion = true;
      addTearDown(() => AppMotion.reduceMotion = false);

      await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 60));

      expect(hasBootPainter(tester), isFalse);
      expect(heroLogo(), findsOneWidget);
      expect(find.text('VisioSoil'), findsNothing);
      expect(find.text('Análise de textura do solo'), findsNothing);
      // "Pular" is a control, not motion: it stays even with motion reduced.
      expect(find.text('Pular'), findsOneWidget);

      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byType(VisioSoilLogo),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, closeTo(60 / 150, 0.05));

      // The fade — and the boot — finish at 150 ms, well under the full
      // entrance's 1.2 s.
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
    },
  );

  testWidgets('reduce_motion_disables_the_hero_flight_for_the_boot_logo', (
    tester,
  ) async {
    AppMotion.reduceMotion = true;
    addTearDown(() => AppMotion.reduceMotion = false);

    await pumpSplash(tester);
    await tester.pump(const Duration(milliseconds: 60));

    final heroMode = tester.widget<HeroMode>(
      find.ancestor(of: heroLogo(), matching: find.byType(HeroMode)).first,
    );
    expect(heroMode.enabled, isFalse);

    await unmount(tester);
  });

  testWidgets('full_motion_renders_the_sieve_mesh_and_grains_painter', (
    tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(hasBootPainter(tester), isTrue);

    await unmount(tester);
  });

  testWidgets('boot_never_vibrates_through_a_full_entrance_and_hand_off', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    await pumpSplash(tester);

    await tester.pump(SplashScreen.heroDelay);
    await tester.pumpAndSettle();

    expect(haptics, isEmpty);
  });

  testWidgets('boot_never_vibrates_when_skipped', (tester) async {
    final haptics = recordHaptics(tester);
    await pumpSplash(tester);

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    expect(haptics, isEmpty);
  });

  testWidgets('boot_background_matches_each_theme', (tester) async {
    for (final (name, theme, expected) in [
      ('light', AppTheme.light, AppPalette.light.primary),
      ('dark', AppTheme.dark, AppPalette.dark.onPrimary),
      ('sun', AppTheme.sun, AppPalette.sun.primary),
    ]) {
      await pumpSplash(tester, theme: theme);

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        expected,
        reason: name,
      );

      await unmount(tester);
    }
  });

  // The boot passes Flutter's four accessibility guidelines (SPEC 0133), with
  // the entrance's fade settled so the logo and name are in the render tree
  // at full opacity, not transparent.
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSplash(tester, theme: theme);
      await tester.pump(const Duration(milliseconds: 600));

      await expectMeetsGuidelines(tester);

      await unmount(tester);
      semantics.dispose();
    });
  }
}

class _FakeStore implements OnboardingStore {
  _FakeStore(this.completed);

  final bool completed;

  @override
  Future<bool> hasCompletedOnboarding() async => completed;

  @override
  Future<void> markOnboardingCompleted() async {}
}
