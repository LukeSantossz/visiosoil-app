import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:visiosoil_app/core/widgets/route_error_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'router_error_builder_renders_route_error_view_for_an_unknown_route',
    (tester) async {
      // A minimal router with the same errorBuilder wiring as appRouter, so the
      // fallback is exercised without appRouter's /splash timer and permission
      // calls.
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const Scaffold()),
        ],
        errorBuilder: (context, state) =>
            RouteErrorView(onGoHome: () => context.go('/')),
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go('/definitely-not-a-route');
      await tester.pumpAndSettle();

      expect(find.byType(RouteErrorView), findsOneWidget);
      expect(find.text('Tela não encontrada'), findsOneWidget);
    },
  );

  group('appRouter', () {
    List<String> topLevelPaths() => appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toList();

    test('does not register the orphan /history route', () {
      expect(topLevelPaths(), isNot(contains('/history')));
    });

    test('still registers the core navigable routes', () {
      expect(
        topLevelPaths(),
        containsAll(<String>[
          '/splash',
          '/',
          '/capture',
          '/details',
          '/preview',
          '/onboarding',
          '/settings',
        ]),
      );
    });
  });
}
