import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/capture_protocol.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';
import '../../support/fake_onboarding_store.dart';
import '../../support/guidelines.dart';
import '../../support/haptics_recorder.dart';
import '../../support/large_text.dart';

class _Auth implements AuthService {
  _Auth({this.result, this.error});
  final AuthAccount? result;
  final Object? error;
  int signInCalls = 0;
  AuthAccount? _account;
  @override
  AuthAccount? get currentAccount => _account;
  @override
  Future<AuthAccount?> restoreSession() async => null;
  @override
  Future<AuthAccount?> signIn() async {
    signInCalls++;
    if (error != null) throw error!;
    return _account = result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _cameraRequests = 0;
Future<AppPermissionStatus> _requestCamera() async {
  _cameraRequests++;
  return AppPermissionStatus.granted;
}

GoRouter _router({required String initialLocation}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, _) =>
              const OnboardingScreen(requestCameraPermission: _requestCamera),
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
  AuthService? auth,
  bool offline = false,
}) =>
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(store),
        authServiceProvider.overrideWithValue(auth ?? _Auth()),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream.value(
            offline ? ConnectivityStatus.offline : ConnectivityStatus.online,
          ),
        ),
      ],
      child: MaterialApp.router(theme: theme, routerConfig: router),
    );

// Moves from the first page to the [step]th (1-based) with the steps' own
// buttons: "Agora não" on the account step, "Continuar" after it.
Future<void> _goToStep(WidgetTester tester, int step) async {
  for (var i = 1; i < step; i++) {
    await _next(tester, i);
  }
}

Future<void> _next(WidgetTester tester, int from) async {
  final button = find.text(from == 1 ? 'Agora não' : 'Continuar');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

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

    await _goToStep(tester, 4);
    await tester.ensureVisible(find.text('Permitir câmera'));
    await tester.tap(find.text('Permitir câmera'));
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

  testWidgets('header_counts_four_steps', (tester) async {
    await tester.pumpWidget(
        _app(_router(initialLocation: '/onboarding'), FakeOnboardingStore()));
    await tester.pumpAndSettle();

    expect(find.text('Passo 1 de 4'), findsOneWidget);
    expect(find.byKey(const Key('onboardingStepBar')), findsNWidgets(4));

    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(find.text('Passo 2 de 4'), findsOneWidget);
  });

  group('account step', () {
    testWidgets('account_step_links_with_google', (tester) async {
      final haptics = recordHaptics(tester);
      final auth = _Auth(
        result: const AuthAccount(
          email: 'ana@exemplo.com',
          displayName: 'Ana Rocha',
        ),
      );
      await tester.pumpWidget(_app(
        _router(initialLocation: '/onboarding'),
        FakeOnboardingStore(),
        auth: auth,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar com o Google'));
      await tester.pumpAndSettle();
      // The linked haptic's second impact follows 90 ms later.
      await tester.pump(const Duration(milliseconds: 100));

      expect(auth.signInCalls, 1);
      expect(find.text('Conta vinculada'), findsOneWidget);
      expect(find.text('Ana Rocha'), findsOneWidget);
      expect(find.text('ana@exemplo.com'), findsOneWidget);
      expect(haptics, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
      ]);

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Passo 2 de 4'), findsOneWidget);
    });

    testWidgets('account_step_offline_disables_google', (tester) async {
      await tester.pumpWidget(_app(
        _router(initialLocation: '/onboarding'),
        FakeOnboardingStore(),
        offline: true,
      ));
      await tester.pumpAndSettle();

      final button =
          find.widgetWithText(OutlinedButton, 'Continuar com o Google');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      expect(
        find.text('Sem conexão. Você pode vincular depois em Perfil.'),
        findsOneWidget,
      );
    });

    testWidgets('account_step_error_shows_snackbar', (tester) async {
      await tester.pumpWidget(_app(
        _router(initialLocation: '/onboarding'),
        FakeOnboardingStore(),
        auth: _Auth(error: Exception('cancelled')),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar com o Google'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Não foi possível vincular. Tente de novo ou continue sem conta.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continuar com o Google'), findsOneWidget);
      expect(find.text('Conta vinculada'), findsNothing);
    });
  });

  // The photograph step still teaches the capture protocol the A4-sheet
  // reader assumes (ADR 0017, SPEC 0104): a photograph taken any other way
  // is refused by name.
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
      for (var i = 1; i <= 4; i++) {
        pages.add(tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .toList());
        if (i < 4) await _next(tester, i);
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

    testWidgets('photo_step_teaches_the_sheet_protocol', (tester) async {
      final page = (await pageTexts(tester))[1];

      expect(page, contains('Fotografe a amostra de solo'));
      final protocol = [for (final s in steps) ...[s.$1, s.$2]];
      expect(protocol, [
        for (final s in captureProtocolSteps) ...[s.title, s.description],
      ]);
      final shown = page.where(protocol.contains).toList();
      expect(shown, protocol);
    });

    testWidgets('class_step_shows_the_triangle', (tester) async {
      await tester.pumpWidget(_app(
        _router(initialLocation: '/onboarding'),
        FakeOnboardingStore(),
      ));
      await tester.pumpAndSettle();
      await _goToStep(tester, 3);

      expect(find.text('Veja a classe textural estimada'), findsOneWidget);
      expect(find.byType(TextureTriangle), findsOneWidget);
    });
  });

  group('camera step', () {
    testWidgets('camera_step_requests_then_completes', (tester) async {
      _cameraRequests = 0;
      final store = FakeOnboardingStore();
      await tester.pumpWidget(
          _app(_router(initialLocation: '/onboarding'), store));
      await tester.pumpAndSettle();
      await _goToStep(tester, 4);

      expect(find.text('Permita o acesso à câmera'), findsOneWidget);
      await tester.ensureVisible(find.text('Permitir câmera'));
      await tester.tap(find.text('Permitir câmera'));
      await tester.pumpAndSettle();

      expect(_cameraRequests, 1);
      expect(store.markCalls, 1);
      expect(find.text('HOME_STUB'), findsOneWidget);
    });

    testWidgets('agora_nao_completes_without_asking', (tester) async {
      _cameraRequests = 0;
      final store = FakeOnboardingStore();
      await tester.pumpWidget(
          _app(_router(initialLocation: '/onboarding'), store));
      await tester.pumpAndSettle();
      await _goToStep(tester, 4);

      await tester.ensureVisible(find.text('Agora não'));
      await tester.tap(find.text('Agora não'));
      await tester.pumpAndSettle();

      expect(_cameraRequests, 0);
      expect(store.markCalls, 1);
      expect(find.text('HOME_STUB'), findsOneWidget);
    });
  });

  // With the platform asking for no animations, a step's button jumps instead of
  // sliding (SPEC 0120). The second test is the control that shows the first
  // one can fail.
  group('reduced motion', () {
    double pageAfterNext(WidgetTester tester) =>
        tester.widget<PageView>(find.byType(PageView)).controller!.page!;

    Future<void> tapNext(WidgetTester tester) async {
      await tester.pumpWidget(
          _app(_router(initialLocation: '/onboarding'), FakeOnboardingStore()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agora não'));
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

    for (var step = 1; step <= 4; step++) {
      expect(tester.takeException(), isNull, reason: 'step $step');
      await scrollToTheEnd(tester);
      expect(tester.takeException(), isNull, reason: 'step $step, scrolled');
      if (step < 4) {
        await _next(tester, step);
      }
    }
  });

  testWidgets('hc_discs_are_solid: the first onboarding disc', (tester) async {
    await tester.pumpWidget(_app(
      _router(initialLocation: '/onboarding'),
      FakeOnboardingStore(),
      theme: AppTheme.lightHighContrast,
    ));
    await tester.pumpAndSettle();

    final disc = tester.widget<Container>(find.byWidgetPredicate((widget) {
      final decoration = widget is Container ? widget.decoration : null;
      return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
    }));
    final decoration = disc.decoration! as BoxDecoration;
    expect(decoration.color, AppPalette.lightHighContrast.primaryContainer);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.cloud_sync_outlined)).color,
      AppPalette.lightHighContrast.onPrimaryContainer,
    );
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
