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

/// Guards the boot "Peneira" (v11 §3.1, §6.2, §7, PR 14, SPEC 0193) as the
/// prototype times it (SPEC 0217): the green reveal, the sieve's ripple, the
/// mark's assembly, the text, the slide-up hand-off, "Pular", reduced motion,
/// and that boot never vibrates.
void main() {
  GoRouter router(bool completed) => GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/',
        pageBuilder: (_, state) => bootHandOffPage(
          state,
          const Scaffold(body: Center(child: Text('HOME_STUB'))),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) => bootHandOffPage(
          state,
          const Scaffold(body: Text('ONBOARDING_STUB')),
        ),
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

  Duration ms(int value) => Duration(milliseconds: value);

  bool hasBootPainter(WidgetTester tester) => find
      .byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString() == '_BootSievePainter',
      )
      .evaluate()
      .isNotEmpty;

  double opacityOf(WidgetTester tester, String text) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  // The boot routes on at this mark, comfortably inside the ≤1.6 s budget.
  // The hand-off's slide runs after it, as every route's transition does.
  test('the_entrance_commits_to_navigating_well_within_the_1_6s_budget', () {
    expect(SplashScreen.handOffAt, ms(1400));
    expect(SplashScreen.handOffAt, lessThanOrEqualTo(ms(1600)));
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
        tester
            .widget<Text>(find.text('Análise de textura do solo'))
            .style
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

  testWidgets('boot_starts_on_the_background_and_opens_green', (tester) async {
    for (final (name, theme, palette) in [
      ('light', AppTheme.light, AppPalette.light),
      ('dark', AppTheme.dark, AppPalette.dark),
      ('sun', AppTheme.sun, AppPalette.sun),
    ]) {
      await pumpSplash(tester, theme: theme);
      final screen = tester.getSize(find.byType(SplashScreen));
      Path reveal() => tester
          .widget<ClipPath>(find.byKey(const Key('boot-reveal')))
          .clipper!
          .getClip(screen);

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        palette.background,
        reason: name,
      );
      expect(
        tester.widget<ColoredBox>(find.byKey(const Key('boot-green'))).color,
        palette.bootBackground,
        reason: name,
      );
      expect(reveal().getBounds().isEmpty, isTrue, reason: name);

      await tester.pump(ms(420));
      final opened = reveal();
      for (final corner in [
        const Offset(.5, .5),
        Offset(screen.width - .5, .5),
        Offset(.5, screen.height - .5),
        Offset(screen.width - .5, screen.height - .5),
      ]) {
        expect(opened.contains(corner), isTrue, reason: '$name $corner');
      }

      await unmount(tester);
    }
  });

  testWidgets('boot_sieve_dots_ripple_and_clear', (tester) async {
    await pumpSplash(tester);
    final sieve = find.byKey(const Key('boot-sieve'));

    await tester.pump(ms(600));
    expect(tester.renderObject(sieve), paints..circle());

    await tester.pump(ms(800));
    expect(tester.renderObject(sieve), isNot(paints..circle()));

    await unmount(tester);
  });

  testWidgets('boot_mark_assembles', (tester) async {
    await pumpSplash(tester);
    final mark = find.byKey(const Key('boot-mark'));
    final screen = tester.getSize(find.byType(SplashScreen));

    final rect = tester.getRect(mark);
    expect(rect.size, const Size.square(88));
    expect(rect.top, screen.height / 2 - 96);
    expect(rect.center.dx, screen.width / 2);

    await tester.pump(ms(500));
    expect(tester.renderObject(mark), isNot(paints..arc()));
    expect(
      tester.renderObject(mark),
      isNot(paints..circle(style: PaintingStyle.stroke)),
    );

    await tester.pump(ms(600));
    expect(
      tester.renderObject(mark),
      paints
        ..circle(style: PaintingStyle.stroke)
        ..circle(style: PaintingStyle.fill)
        ..circle(style: PaintingStyle.fill)
        ..circle(style: PaintingStyle.fill)
        ..line(),
    );

    await unmount(tester);
  });

  testWidgets('boot_text_rises_after_the_mark', (tester) async {
    await pumpSplash(tester);

    await tester.pump(ms(900));
    expect(opacityOf(tester, 'VisioSoil'), 0);
    expect(opacityOf(tester, 'Análise de textura do solo'), 0);

    await tester.pump(ms(400));
    expect(opacityOf(tester, 'VisioSoil'), 1);

    await unmount(tester);
  });

  testWidgets('pular_fades_in_and_turns_white_with_the_green', (tester) async {
    await pumpSplash(tester);

    expect(opacityOf(tester, 'Pular'), 0);
    expect(
      tester.widget<Text>(find.text('Pular')).style?.color,
      AppPalette.light.primaryText,
    );

    await tester.pump(ms(500));
    expect(opacityOf(tester, 'Pular'), 1);
    expect(tester.widget<Text>(find.text('Pular')).style?.color, Colors.white);

    await unmount(tester);
  });

  testWidgets('boot_hands_off_by_sliding_up', (tester) async {
    await pumpSplash(tester);

    await tester.pump(SplashScreen.handOffAt);
    // GoRouter parses the new location asynchronously: two frames.
    await tester.pump(ms(1));
    await tester.pump(ms(1));
    expect(find.text('HOME_STUB'), findsOneWidget);

    await tester.pump(ms(200));
    final curtain = find.byKey(const Key('boot-curtain'));
    expect(tester.getRect(curtain).top, lessThan(0));
    final risingTop = tester.getTopLeft(find.text('HOME_STUB')).dy;

    await tester.pump(ms(340));
    await tester.pump();
    expect(curtain, findsNothing);
    expect(find.byType(SplashScreen), findsNothing);
    expect(
      risingTop,
      greaterThan(tester.getTopLeft(find.text('HOME_STUB')).dy),
    );
  });

  testWidgets('boot_navigates_home_within_the_1_6s_budget', (tester) async {
    await pumpSplash(tester);

    await tester.pump(SplashScreen.handOffAt);
    await tester.pumpAndSettle();

    expect(find.text('HOME_STUB'), findsOneWidget);
    expect(find.text('ONBOARDING_STUB'), findsNothing);
  });

  testWidgets('first_launch_routes_to_onboarding_instead_of_home', (
    tester,
  ) async {
    await pumpSplash(tester, completed: false);

    await tester.pump(SplashScreen.handOffAt);
    await tester.pumpAndSettle();

    expect(find.text('ONBOARDING_STUB'), findsOneWidget);
  });

  testWidgets('pular_navigates_immediately_without_waiting_for_the_entrance', (
    tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump(ms(500));

    await tester.tap(find.text('Pular'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('boot-curtain')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('pular_causes_no_double_navigation_once_the_entrance_would_end', (
    tester,
  ) async {
    await pumpSplash(tester);
    await tester.pump(ms(500));

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The entrance's own hand-off mark, had Pular not already left: must not
    // throw or navigate a second time (the splash is gone, undisposed timer
    // would also fail the test on its own).
    await tester.pump(SplashScreen.handOffAt);
    expect(tester.takeException(), isNull);
  });

  // Home draws no logo (PNG 08), so the boot has nothing to fly a Hero to.
  testWidgets('boot_carries_no_logo_hero', (tester) async {
    await pumpSplash(tester);

    expect(find.byType(Hero), findsNothing);

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
      await tester.pump(ms(60));

      expect(hasBootPainter(tester), isFalse);
      expect(find.byType(VisioSoilLogo), findsOneWidget);
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

      // The fade — and the boot — finish at 150 ms, and the route changes
      // with no transition: no curtain slides.
      await tester.pump(ms(90));
      // GoRouter parses the new location asynchronously.
      await tester.pump(ms(1));
      await tester.pump(ms(1));
      expect(find.byKey(const Key('boot-curtain')), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('HOME_STUB'), findsOneWidget);
    },
  );

  testWidgets('full_motion_renders_the_sieve_painter', (tester) async {
    await pumpSplash(tester);
    await tester.pump(ms(300));

    expect(hasBootPainter(tester), isTrue);

    await unmount(tester);
  });

  testWidgets('boot_never_vibrates_through_a_full_entrance_and_hand_off', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    await pumpSplash(tester);

    await tester.pump(SplashScreen.handOffAt);
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

  // The boot passes Flutter's four accessibility guidelines (SPEC 0133),
  // just before it routes on, with the mark, the name, the tagline and
  // "Pular" all in at full opacity on the green.
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSplash(tester, theme: theme);
      await tester.pump(ms(1390));

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
