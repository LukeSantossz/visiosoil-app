// Rows, the history toggle and the onboarding stay whole on a narrow phone
// and at large text (SPEC 0222).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/swipe_to_delete.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../support/fake_onboarding_store.dart';
import '../support/fake_soil_record_repository.dart';
import '../support/haptics_recorder.dart';

final _records = [
  for (var id = 1; id <= 3; id++)
    SoilRecord(
      id: id,
      imagePath: 'missing.png',
      timestamp: DateTime(2026, 10, 27, 12, id).toIso8601String(),
      textureClass: 'Argilosa',
      confidenceScore: .82,
    ),
];

void _narrow(WidgetTester tester, {bool largeText = true}) {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.reset);
  if (largeText) {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

Future<void> _pumpHistory(WidgetTester tester) async {
  final data = AsyncData(_records);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        soilRecordRepositoryProvider.overrideWithValue(
          FakeSoilRecordRepository(),
        ),
        soilRecordsStreamProvider.overrideWithValue(data),
        filteredRecordsProvider.overrideWithValue(data),
        connectivityStatusProvider.overrideWithValue(
          const AsyncData(ConnectivityStatus.online),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const HistoryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _Auth implements AuthService {
  @override
  AuthAccount? get currentAccount => null;
  @override
  Future<AuthAccount?> restoreSession() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpOnboarding(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingStoreProvider.overrideWithValue(FakeOnboardingStore()),
        authServiceProvider.overrideWithValue(_Auth()),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream.value(ConnectivityStatus.online),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: OnboardingScreen(
          requestCameraPermission: () async => AppPermissionStatus.granted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The four steps' titles, in order, and the action that leaves each.
const _steps = [
  ('Vincular conta para salvar e sincronizar suas análises', 'Agora não'),
  ('Fotografe a amostra de solo', 'Continuar'),
  ('Veja a classe textural estimada', 'Continuar'),
  ('Permita o acesso à câmera', null),
];

Future<void> _next(WidgetTester tester, String action) async {
  await tester.tap(find.text(action).first);
  await tester.pumpAndSettle();
}

final _vertical = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

void main() {
  group('history row', () {
    Future<(Rect, Rect)> reveal(WidgetTester tester) async {
      recordHaptics(tester);
      _narrow(tester);
      await _pumpHistory(tester);
      final row = find.byType(SwipeToDelete).first;
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final before = tester.getRect(row);
      // The row's trailing chevron: no sync status shows while no backend is
      // wired (SPEC 0235).
      final chevron = find.descendant(
        of: row,
        matching: find.byIcon(LucideIcons.chevronRight),
      );
      final chevronBefore = tester.getRect(chevron);
      final visible = before.intersect(
        tester.getRect(find.byType(CustomScrollView)),
      );
      await tester.dragFrom(visible.center, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(row), before);
      expect(tester.getSize(chevron).height, chevronBefore.height);
      return (before, chevronBefore);
    }

    testWidgets('revealed_row_keeps_its_size', (tester) async {
      await reveal(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('revealed_row_recedes_under_the_action', (tester) async {
      final (row, chevron) = await reveal(tester);
      final content = find.descendant(
        of: find.byType(SwipeToDelete).first,
        matching: find.byIcon(LucideIcons.chevronRight),
      );
      // PNG 34: the row recedes 12 dp and "Excluir" covers its end.
      expect(tester.getRect(content).left, closeTo(chevron.left - 12, .01));
      expect(tester.getSize(content).width, closeTo(chevron.width, .01));
      final action = tester.getRect(
        find.descendant(
          of: find.byType(SwipeToDelete).first,
          matching: find.widgetWithText(InkWell, 'Excluir'),
        ),
      );
      expect(action.width, 104);
      expect(action.right, row.right);
    });
  });

  testWidgets('history_toggle_fits_at_large_text', (tester) async {
    _narrow(tester);
    await _pumpHistory(tester);

    for (final label in ['Análises', 'Coleção']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0), reason: label);
      expect(rect.right, lessThanOrEqualTo(320), reason: label);
    }
    expect(
      find.ancestor(
        of: find.byType(SegmentedControl<bool>),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      ),
      findsNothing,
    );
  });

  group('onboarding', () {
    double panelHeight(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('onboarding-panel')).first).height;

    testWidgets('onboarding_panel_is_short_on_small_screens', (tester) async {
      _narrow(tester, largeText: false);
      await _pumpOnboarding(tester);
      for (final (_, action) in _steps) {
        expect(panelHeight(tester), 200 + 24);
        if (action != null) await _next(tester, action);
      }

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(panelHeight(tester), 376 + 24);
    });

    testWidgets('onboarding_fits_small_screens_at_large_text', (tester) async {
      _narrow(tester);
      await _pumpOnboarding(tester);
      for (final (title, action) in _steps) {
        expect(tester.takeException(), isNull, reason: title);
        await tester.scrollUntilVisible(
          find.text(title),
          40,
          scrollable: _vertical.first,
        );
        expect(tester.getRect(find.text(title)).top, greaterThanOrEqualTo(0));
        for (final button
            in find
                .byWidgetPredicate((w) => w is ButtonStyleButton)
                .evaluate()) {
          final rect = tester.getRect(find.byWidget(button.widget));
          expect(rect.bottom, lessThanOrEqualTo(568), reason: title);
        }
        if (action != null) await _next(tester, action);
      }
    });
  });
}
