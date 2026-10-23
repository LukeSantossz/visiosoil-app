// Settings' theme choice applies at once, persists, and reaches the platform so
// the next native launch follows it (SPEC 0107).
// Vibration and reduce motion preferences also apply and persist (redesign v11 PR4).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
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

  bool highContrast = false;

  @override
  Future<bool> readHighContrast() async => highContrast;

  @override
  Future<void> writeHighContrast(bool on) async => highContrast = on;

  bool vibration = true;

  @override
  Future<bool> readVibration() async => vibration;

  @override
  Future<void> writeVibration(bool on) async => vibration = on;

  bool reduceMotion = false;

  @override
  Future<bool> readReduceMotion() async => reduceMotion;

  @override
  Future<void> writeReduceMotion(bool on) async => reduceMotion = on;
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
  // Reset AppHaptics.enabled before each test to ensure clean state
  AppHaptics.enabled = true;

  await tester.pumpWidget(ProviderScope(
    overrides: [
      initialThemeModeProvider.overrideWithValue(ThemeMode.system),
      appearanceStoreProvider.overrideWithValue(store),
      nightModeSyncProvider.overrideWithValue(sync),
      initialVibrationProvider.overrideWithValue(store.vibration),
      initialReduceMotionProvider.overrideWithValue(store.reduceMotion),
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

  // The switch applies high contrast at once and persists it (SPEC 0130).
  testWidgets('high_contrast_is_a_setting', (tester) async {
    final store = _MemoryStore();
    await _pumpSettings(tester, store, _RecordingSync());

    bool highContrast() =>
        tester.element(find.byType(SettingsScreen)).palette.highContrast;
    final toggle = find.widgetWithText(SwitchListTile, 'Alto contraste');
    expect(highContrast(), isFalse);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(highContrast(), isTrue);
    expect(store.highContrast, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(highContrast(), isFalse);
    expect(store.highContrast, isFalse);
  });

  // Vibration toggle: off silences all haptics, persists (redesign v11 §3.11/§7).
  testWidgets('vibration_toggle_silences_haptics_and_persists', (tester) async {
    final store = _MemoryStore();
    final haptics = recordHaptics(tester);
    await _pumpSettings(tester, store, _RecordingSync());

    // Find the vibration toggle by its subtitle (spec copy: "Toques sutis...")
    final toggle = find.widgetWithText(SwitchListTile, 'Vibração');
    expect(toggle, findsOneWidget);
    expect(AppHaptics.enabled, isTrue);
    expect(store.vibration, isTrue);

    // Turn off: should silence haptics and persist
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(AppHaptics.enabled, isFalse);
    expect(store.vibration, isFalse);

    // Verify no haptics fire when disabled
    haptics.clear();
    await AppHaptics.selection();
    expect(haptics, isEmpty);

    // Turn back on: fires confirm() as sample and persists (spec: §7)
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(AppHaptics.enabled, isTrue);
    expect(store.vibration, isTrue);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
  });

  // Reduce motion toggle persists and follows system by default (redesign v11 §3.11/§6.5).
  testWidgets('reduce_motion_toggle_persists', (tester) async {
    final store = _MemoryStore();
    await _pumpSettings(tester, store, _RecordingSync());

    final toggle = find.widgetWithText(SwitchListTile, 'Reduzir movimento');
    expect(toggle, findsOneWidget);
    expect(store.reduceMotion, isFalse);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.reduceMotion, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.reduceMotion, isFalse);
  });

  // Reduce motion does NOT silence haptics (spec §6.5: "Os haptics continuam").
  testWidgets('reduce_motion_does_not_silence_haptics', (tester) async {
    final store = _MemoryStore()..reduceMotion = true;
    final haptics = recordHaptics(tester);
    await _pumpSettings(tester, store, _RecordingSync());

    await AppHaptics.selection();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  // Selection click fires on vibration toggle (spec §7: selection for toggles).
  testWidgets('selection_clicks: vibration toggle', (tester) async {
    final haptics = recordHaptics(tester);
    await _pumpSettings(tester, _MemoryStore(), _RecordingSync());

    final toggle = find.widgetWithText(SwitchListTile, 'Vibração');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Turn off: no haptic (vibration is now disabled)
    expect(haptics, isEmpty);

    // Turn on: confirm() sample fires after selection()
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    // Last haptic should be the confirm() sample
    expect(haptics.last, 'HapticFeedbackType.lightImpact');
  });
}
