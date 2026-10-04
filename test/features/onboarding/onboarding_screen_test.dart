import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';
import '../../support/fake_onboarding_store.dart';
import '../../support/guidelines.dart';
import '../../support/large_text.dart';

GoRouter _router({required String initialLocation}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME_STUB')),
        ),
        GoRoute(
          path: '/host',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.push('/onboarding'),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ],
    );

Widget _app(
  GoRouter router,
  FakeOnboardingStore store, {
  ThemeData? theme,
}) =>
    ProviderScope(
      overrides: [onboardingStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(theme: theme, routerConfig: router),
    );

void main() {
  testWidgets('skipping marks completion and goes home when it cannot pop',
      (tester) async {
    final store = FakeOnboardingStore();
    await tester.pumpWidget(_app(_router(initialLocation: '/onboarding'), store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    expect(store.markCalls, 1);
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('finishing the last step marks completion and goes home',
      (tester) async {
    final store = FakeOnboardingStore();
    await tester.pumpWidget(_app(_router(initialLocation: '/onboarding'), store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();

    expect(store.markCalls, 1);
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('when opened over a route, completing pops back', (tester) async {
    final store = FakeOnboardingStore();
    await tester.pumpWidget(_app(_router(initialLocation: '/host'), store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    expect(store.markCalls, 1);
    expect(find.text('OPEN'), findsOneWidget); // back on the host route
    expect(find.text('Pular'), findsNothing); // onboarding is gone
  });

  // The steps teach the capture protocol the A4-sheet reader assumes (ADR 0017,
  // SPEC 0104): a photograph taken any other way is refused by name.
  group('copy', () {
    const steps = [
      (
        'Folha A4',
        'Use uma folha A4 branca, sem nada escrito, sobre uma superfície '
            'mais escura que o papel. Não coloque mais nada sobre ela.',
      ),
      ('Amostra', 'Espalhe o solo em um círculo de 8 a 10 cm no meio da folha.'),
      (
        'Foto',
        'Fotografe de cima, com a folha inteira no quadro e uma margem em '
            'volta, em luz difusa e sem flash.',
      ),
    ];

    // Pumps the onboarding and returns the text of each page, in order.
    Future<List<List<String>>> pageTexts(WidgetTester tester) async {
      await tester.pumpWidget(_app(
        _router(initialLocation: '/onboarding'),
        FakeOnboardingStore(),
      ));
      await tester.pumpAndSettle();
      final pages = <List<String>>[];
      for (var i = 0; i < steps.length; i++) {
        pages.add(tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .toList());
        if (i < steps.length - 1) {
          await tester.tap(find.text('Próximo'));
          await tester.pumpAndSettle();
        }
      }
      return pages;
    }

    testWidgets('no_step_mentions_a_coin_or_a_viewfinder', (tester) async {
      final texts = (await pageTexts(tester)).expand((page) => page);

      for (final text in texts) {
        expect(text.toLowerCase(), isNot(contains('moeda')));
        expect(text.toLowerCase(), isNot(contains('visor')));
      }
    });

    testWidgets('the_steps_teach_the_sheet_protocol_in_order', (tester) async {
      final pages = await pageTexts(tester);

      for (var i = 0; i < steps.length; i++) {
        expect(pages[i], containsAll([steps[i].$1, steps[i].$2]),
            reason: 'step ${i + 1}');
      }
    });
  });

  // With the platform asking for no animations, "Próximo" jumps instead of
  // sliding (SPEC 0120). The second test is the control that shows the first
  // one can fail.
  group('reduced motion', () {
    double pageAfterNext(WidgetTester tester) =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page!;

    Future<void> tapNext(WidgetTester tester) async {
      await tester.pumpWidget(
          _app(_router(initialLocation: '/onboarding'), FakeOnboardingStore()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Próximo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('onboarding_step_jumps_without_motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await tapNext(tester);

      expect(pageAfterNext(tester), 1);
    });

    testWidgets('onboarding_step_slides_with_motion', (tester) async {
      await tapNext(tester);

      expect(pageAfterNext(tester), allOf(greaterThan(0), lessThan(1)));
      await tester.pumpAndSettle();
    });
  });

  // At 200 % text on a phone, each step still lays out (SPEC 0121).
  testWidgets('onboarding_scales_to_200_percent', (tester) async {
    useLargeTextOnAPhone(tester);
    await tester.pumpWidget(
        _app(_router(initialLocation: '/onboarding'), FakeOnboardingStore()));
    await tester.pumpAndSettle();

    for (var step = 1; step <= 3; step++) {
      expect(tester.takeException(), isNull, reason: 'step $step');
      await scrollToTheEnd(tester);
      expect(tester.takeException(), isNull, reason: 'step $step, scrolled');
      if (step < 3) {
        await tester.tap(find.text('Próximo'));
        await tester.pumpAndSettle();
      }
    }
  });

  // The first step passes Flutter's four accessibility guidelines
  // (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(
        _router(initialLocation: '/onboarding'),
        FakeOnboardingStore(),
        theme: theme,
      ));
      await tester.pumpAndSettle();
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}
