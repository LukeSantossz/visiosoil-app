import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
