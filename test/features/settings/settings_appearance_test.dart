// Settings' theme choice applies at once, persists, and reaches the platform so
// the next native launch follows it (SPEC 0107, SPEC 0184).
// Vibration and reduce motion preferences also apply and persist (redesign v11 PR4).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/widgets/settings_switch_tile.dart';
import 'package:visiosoil_app/core/widgets/settings_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/main.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/capture_preferences_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';

import '../../support/guidelines.dart';
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
  ThemeMode base = ThemeMode.system;

  @override
  Future<ThemeMode> readBaseThemeMode() async => base;

  @override
  Future<void> writeBaseThemeMode(ThemeMode mode) async => base = mode;

  bool sun = false;

  @override
  Future<bool> readSunMode() async => sun;

  @override
  Future<void> writeSunMode(bool on) async => sun = on;

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
  SharedPreferences.setMockInitialValues({});
  // Reset AppHaptics.enabled before each test to ensure clean state
  AppHaptics.enabled = true;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialBaseThemeModeProvider.overrideWithValue(store.base),
        initialSunModeProvider.overrideWithValue(store.sun),
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
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings_switches_the_base_theme', (tester) async {
    final store = _MemoryStore();
    final sync = _RecordingSync();
    await _pumpSettings(tester, store, sync);

    Brightness brightness() =>
        Theme.of(tester.element(find.byType(SettingsScreen))).brightness;

    // No stored choice yet: the theme follows the test view's platform,
    // which is light.
    expect(find.text('PREFERÊNCIAS'), findsOneWidget);
    expect(brightness(), Brightness.light);

    for (final (label, mode, expected) in [
      ('Escuro', ThemeMode.dark, Brightness.dark),
      ('Claro', ThemeMode.light, Brightness.light),
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(brightness(), expected, reason: label);
      expect(store.base, mode, reason: label);
      expect(sync.applied.last, nightModeFor(mode, sun: false), reason: label);
    }
    expect(sync.applied, [ThemeMode.dark, ThemeMode.light]);
  });

  // PNG 23 offers Claro | Escuro. Until one is chosen the theme follows the
  // system, and the control marks the brightness the system gives (SPEC 0204).
  testWidgets('theme_without_a_choice_shows_the_system_brightness', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = _MemoryStore();
    await _pumpSettings(tester, store, _RecordingSync());

    final control = tester.widget<SegmentedControl<ThemeMode>>(
      find.descendant(
        of: find.byKey(const Key('theme-row')),
        matching: find.byType(SegmentedControl<ThemeMode>),
      ),
    );
    expect(control.value, ThemeMode.dark);
    expect(store.base, ThemeMode.system);
  });

  // Modo Sol is a separate switch that overrides whichever base theme is
  // chosen, and turning it off returns to that base (SPEC 0184).
  testWidgets(
    'modo_sol_overrides_the_base_theme_and_turning_it_off_restores_it',
    (tester) async {
      final store = _MemoryStore();
      final sync = _RecordingSync();
      await _pumpSettings(tester, store, sync);

      bool isSun() => tester.element(find.byType(SettingsScreen)).palette.isSun;
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(SettingsScreen))).brightness;

      await tester.ensureVisible(find.text('Escuro'));
      await tester.tap(find.text('Escuro'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);

      final sunSwitch = find.widgetWithText(SettingsSwitchTile, 'Modo Sol');
      await tester.ensureVisible(sunSwitch);
      await tester.tap(sunSwitch);
      await tester.pumpAndSettle();

      expect(isSun(), isTrue);
      expect(store.sun, isTrue);
      expect(store.base, ThemeMode.dark);
      expect(sync.applied.last, ThemeMode.light);

      await tester.tap(sunSwitch);
      await tester.pumpAndSettle();

      expect(isSun(), isFalse);
      expect(store.sun, isFalse);
      expect(brightness(), Brightness.dark);
      expect(sync.applied.last, ThemeMode.dark);
    },
  );

  // There is no "Modo Sol" segment in the base selector: it is reached only
  // through its own switch (redesign v11 §3.11, SPEC 0184).
  testWidgets('theme_selector_offers_claro_and_escuro', (tester) async {
    await _pumpSettings(tester, _MemoryStore(), _RecordingSync());

    expect(find.text('Sistema'), findsNothing);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Escuro'), findsOneWidget);
    expect(find.widgetWithText(SettingsSwitchTile, 'Modo Sol'), findsOneWidget);
  });

  // PNG 23's icons, and the chevrons on Unidades and Idioma, which open the
  // one choice each has today (SPEC 0204).
  testWidgets('units_and_language_open_their_choice', (tester) async {
    await _pumpSettings(tester, _MemoryStore(), _RecordingSync());

    expect(find.byIcon(LucideIcons.rulerDimensionLine), findsOneWidget);
    expect(find.byIcon(LucideIcons.languages), findsOneWidget);
    expect(find.byIcon(LucideIcons.focus), findsOneWidget);

    for (final (title, option) in [
      ('Unidades', 'Centímetros (cm)'),
      ('Idioma', 'Português (Brasil)'),
    ]) {
      final row = find.widgetWithText(SettingsTile, title);
      await tester.scrollUntilVisible(find.text(title), 120);
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(LucideIcons.chevronRight),
        ),
        findsOneWidget,
        reason: title,
      );

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget, reason: title);
      expect(
        find.descendant(of: sheet, matching: find.text(option)),
        findsOneWidget,
        reason: title,
      );
      expect(
        find.descendant(of: sheet, matching: find.byIcon(LucideIcons.check)),
        findsOneWidget,
        reason: title,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    }
  });

  // The three capture switches act and persist (SPEC 0208).
  testWidgets('capture_switches_are_live', (tester) async {
    await _pumpSettings(tester, _MemoryStore(), _RecordingSync());

    for (final (title, key, initial) in [
      ('Guia de enquadramento', CapturePreferenceKeys.frameGuide, true),
      ('Salvar fotos na galeria', CapturePreferenceKeys.saveToGallery, false),
      ('Registrar localização', CapturePreferenceKeys.recordLocation, true),
    ]) {
      final row = find.widgetWithText(SettingsSwitchTile, title);
      await tester.scrollUntilVisible(find.text(title), 120);
      var tile = tester.widget<SettingsSwitchTile>(row);
      expect(tile.onChanged, isNotNull, reason: title);
      expect(tile.value, initial, reason: title);

      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      tile = tester.widget<SettingsSwitchTile>(row);
      expect(tile.value, !initial, reason: title);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool(key), !initial, reason: title);
    }
  });

  // The legacy "Alto contraste" switch is gone (SPEC 0184); the platform's
  // own high-contrast signal still works, unrelated to any manual switch.
  testWidgets('there_is_no_alto_contraste_switch', (tester) async {
    await _pumpSettings(tester, _MemoryStore(), _RecordingSync());

    expect(
      find.widgetWithText(SettingsSwitchTile, 'Alto contraste'),
      findsNothing,
    );
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

  // Vibration toggle: off silences all haptics, persists (redesign v11 §3.11/§7).
  testWidgets('vibration_toggle_silences_haptics_and_persists', (tester) async {
    final store = _MemoryStore();
    final haptics = recordHaptics(tester);
    await _pumpSettings(tester, store, _RecordingSync());

    // Find the vibration toggle by its subtitle (spec copy: "Toques sutis...")
    final toggle = find.widgetWithText(SettingsSwitchTile, 'Vibração');
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

    final toggle = find.widgetWithText(SettingsSwitchTile, 'Reduzir movimento');
    await tester.scrollUntilVisible(toggle, 250);
    expect(toggle, findsOneWidget);
    expect(store.reduceMotion, isFalse);

    // The list estimates the rows it has not built yet, so the first pass
    // can stop short of the row; a second lands on it.
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
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

    final toggle = find.widgetWithText(SettingsSwitchTile, 'Vibração');
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

  // Modo Sol's own 56 dp minimum (redesign v11 §1.4, SPEC 0182), stricter
  // than the platform's 48 dp androidTapTargetGuideline.
  testWidgets('sol_meets_the_56dp_tap_target_guideline', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpSettings(tester, _MemoryStore()..sun = true, _RecordingSync());

    await expectLater(tester, meetsGuideline(sunTapTargetGuideline));
    semantics.dispose();
  });
}
