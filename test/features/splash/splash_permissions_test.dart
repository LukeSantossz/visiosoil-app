// The splash asks for no permission (SPEC 0099): capture asks for the camera
// and location when it needs them, after onboarding has said what the app is
// for. Driven through a router, with permission_handler's channel recorded, so
// any request the splash makes is seen whichever API it goes through.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/splash/splash_screen.dart';
import 'package:visiosoil_app/core/services/onboarding_store.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

class _FirstLaunch implements OnboardingStore {
  @override
  Future<bool> hasCompletedOnboarding() async => false;

  @override
  Future<void> markOnboardingCompleted() async {}
}

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

void main() {
  testWidgets('first_launch_requests_no_permission', (tester) async {
    final calls = <String>[];
    // Answers every request as granted, so a splash that still asks fails on
    // the recorded call rather than on a malformed reply.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _permissions,
      (call) async {
        calls.add(call.method);
        if (call.method == 'requestPermissions') {
          return {for (final p in call.arguments as List) p: 1};
        }
        return 1;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissions, null));

    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Scaffold(body: Text('ONBOARDING_STUB')),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME_STUB')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingStoreProvider.overrideWithValue(_FirstLaunch())],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(calls, isEmpty);
    expect(find.text('ONBOARDING_STUB'), findsOneWidget);
  });
}
