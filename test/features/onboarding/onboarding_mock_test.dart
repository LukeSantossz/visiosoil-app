// The onboarding follows PNG 02 to 07 as SPEC 0206 measures them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

class _Auth implements AuthService {
  _Auth([this.account]);
  final AuthAccount? account;
  @override
  AuthAccount? get currentAccount => account;
  @override
  Future<AuthAccount?> restoreSession() async => account;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  AuthAccount? account,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(FakeOnboardingStore()),
        authServiceProvider.overrideWithValue(_Auth(account)),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream.value(ConnectivityStatus.online),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: OnboardingScreen(
          requestCameraPermission: () async => AppPermissionStatus.granted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _toStep2(WidgetTester tester) async {
  await tester.tap(find.text('Agora não'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('panel_matches_the_mock', (tester) async {
    await _pump(tester);

    final panel = find.byKey(const Key('onboarding-panel')).first;
    expect(tester.getTopLeft(panel).dy, 0);
    expect(tester.getBottomLeft(panel).dy, 420);
    final box = tester.widget<Container>(panel);
    expect(
      (box.decoration! as BoxDecoration).color,
      AppPalette.light.surfaceContainer,
    );
    expect(find.byKey(const Key('onboarding-contours')), findsWidgets);
  });

  testWidgets('step_text_is_left_aligned', (tester) async {
    await _pump(tester);

    final headline = find.text(
      'Vincular conta para salvar e sincronizar suas análises',
    );
    expect(tester.getTopLeft(headline).dx, 24);
    expect(tester.widget<Text>(headline).style?.fontSize, 28);
    final bar = find.byKey(const Key('onboardingStepBar')).first;
    expect(
      tester.getTopLeft(find.text('Passo 1 de 4')).dy,
      greaterThan(tester.getBottomLeft(bar).dy),
    );
    expect(find.text('Pular'), findsNothing);
  });

  testWidgets('actions_are_pinned_to_the_bottom', (tester) async {
    await _pump(tester);
    expect(
      find.widgetWithText(OutlinedButton, 'Agora não'),
      findsOneWidget,
    );

    await _toStep2(tester);
    final next = find.widgetWithText(ElevatedButton, 'Continuar').first;
    final skip = find.widgetWithText(TextButton, 'Pular').first;
    expect(tester.getSize(next).height, 48);
    expect(tester.getTopLeft(skip).dy, greaterThan(tester.getBottomLeft(next).dy));
    expect(tester.getBottomLeft(skip).dy, 844 - 24);
  });

  testWidgets('linked_row_matches_the_mock', (tester) async {
    await _pump(
      tester,
      account: const AuthAccount(
        email: 'ana@exemplo.com',
        displayName: 'Ana Ribeiro',
      ),
    );

    expect(find.text('Conta vinculada'), findsOneWidget);
    final row = find.byKey(const Key('linked-account-row'));
    for (final text in ['AR', 'Ana Ribeiro', 'ana@exemplo.com']) {
      expect(find.descendant(of: row, matching: find.text(text)), findsOneWidget);
    }
    expect(
      find.descendant(of: row, matching: find.byIcon(LucideIcons.cloudCheck)),
      findsOneWidget,
    );
    // 16 dp above "Continuar", as PNG 04 draws it.
    expect(
      tester.getTopLeft(find.text('Continuar').first).dy -
          tester.getBottomLeft(row).dy,
      greaterThanOrEqualTo(16),
    );
    final continuar = find.ancestor(
      of: find.text('Continuar'),
      matching: find.byType(ElevatedButton),
    );
    expect(
      tester.getTopLeft(continuar).dy - tester.getBottomLeft(row).dy,
      16,
    );
    final icon = tester.widget<Icon>(
      find.descendant(of: row, matching: find.byIcon(LucideIcons.cloudCheck)),
    );
    expect(icon.size, 20);
  });

  // PNG 06 marks the medium class, and the triangle spans 146 dp.
  testWidgets('class_step_highlights_the_class', (tester) async {
    await _pump(tester);
    await _toStep2(tester);
    await tester.tap(find.text('Continuar').first);
    await tester.pumpAndSettle();

    final triangle = find.byType(TextureTriangle);
    expect(tester.widget<TextureTriangle>(triangle).highlightClass, 'Media');
    expect(tester.getSize(triangle).width, closeTo(146 / 170 * 300, .01));
  });

  // PNG 07's list ends above the actions without being cut.
  testWidgets('camera_step_list_is_not_cut', (tester) async {
    await _pump(tester);
    await _toStep2(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Continuar').first);
      await tester.pumpAndSettle();
    }

    // The content scrolls to 8 dp above the first action.
    final content = find.ancestor(
      of: find.text('Permita o acesso à câmera'),
      matching: find.byType(SingleChildScrollView),
    );
    final allow = find.ancestor(
      of: find.text('Permitir câmera'),
      matching: find.byType(ElevatedButton),
    );
    expect(
      tester.getTopLeft(allow).dy - tester.getBottomLeft(content).dy,
      8,
    );
  });

  // PNG 05 has no list; the capture guide teaches the protocol before the
  // first camera launch (SPEC 0142).
  testWidgets('photo_step_has_no_protocol_list', (tester) async {
    await _pump(tester);
    await _toStep2(tester);

    expect(find.text('Fotografe a amostra de solo'), findsOneWidget);
    for (final step in captureProtocolSteps) {
      expect(find.text(step.title), findsNothing);
    }
  });
}
