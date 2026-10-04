// Settings' theme choice applies at once, persists, and reaches the platform so
// the next native launch follows it (SPEC 0107).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/main.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';

import '../../support/haptics_recorder.dart';

/// Signed out. Anything else the screen does not reach falls to noSuchMethod.
class _SignedOut implements AuthService {
  @override
  AuthAccount? get currentAccount => null;

  @override
  Future<AuthAccount?> restoreSession() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStore implements AppearanceStore {
  ThemeMode stored = ThemeMode.system;

  @override
  Future<ThemeMode> read() async => stored;

  @override
  Future<void> write(ThemeMode mode) async => stored = mode;
}

class _RecordingSync implements NightModeSync {
  final applied = <ThemeMode>[];

  @override
  Future<void> apply(ThemeMode mode) async => applied.add(mode);
}

Future<void> _pumpSettings(
  WidgetTester tester,
  _MemoryStore store,
  _RecordingSync sync,
) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialThemeModeProvider.overrideWithValue(ThemeMode.system),
      appearanceStoreProvider.overrideWithValue(store),
      nightModeSyncProvider.overrideWithValue(sync),
      authServiceProvider.overrideWithValue(_SignedOut()),
      packageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'VisioSoil',
          packageName: 'com.visiosoil.app',
          version: '1.0.0',
          buildNumber: '1',
        ),
      ),
    ],
    child: VisioSoilApp(
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings_switches_the_theme', (tester) async {
    final store = _MemoryStore();
    final sync = _RecordingSync();
    await _pumpSettings(tester, store, sync);

    Brightness brightness() =>
        Theme.of(tester.element(find.byType(SettingsScreen))).brightness;

    // The test view's platform is light, so "Sistema" reads as light.
    expect(find.text('APARÊNCIA'), findsOneWidget);
    expect(brightness(), Brightness.light);

    for (final (label, mode, expected) in [
      ('Escuro', ThemeMode.dark, Brightness.dark),
      ('Claro', ThemeMode.light, Brightness.light),
      ('Sistema', ThemeMode.system, Brightness.light),
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(brightness(), expected, reason: label);
      expect(store.stored, mode, reason: label);
      expect(sync.applied.last, mode, reason: label);
    }
    expect(sync.applied, [ThemeMode.dark, ThemeMode.light, ThemeMode.system]);
  });

  // Choosing a theme is a selection, confirmed by one click (SPEC 0126).
  testWidgets('selection_clicks: the theme choice', (tester) async {
    final haptics = recordHaptics(tester);
    await _pumpSettings(tester, _MemoryStore(), _RecordingSync());

    await tester.ensureVisible(find.text('Escuro'));
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();

    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });
}
