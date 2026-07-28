import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';
import '../../support/fake_onboarding_store.dart';

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

Widget _app(GoRouter router, FakeOnboardingStore store) => ProviderScope(
      overrides: [onboardingStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(routerConfig: router),
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
}
