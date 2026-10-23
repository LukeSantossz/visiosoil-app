import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';

/// Where the theme choice is persisted. Overridden with a fake in tests.
final appearanceStoreProvider = Provider<AppearanceStore>(
  (ref) => SharedPreferencesAppearanceStore(),
);

/// How the theme choice reaches the platform's launch. Overridden in tests.
final nightModeSyncProvider = Provider<NightModeSync>(
  (ref) => defaultNightModeSync(),
);

/// The choice read before `runApp`, so the first frame is already in it.
/// `main` overrides it with the stored value. `null` means no explicit choice
/// was ever made, so the app follows the system brightness (redesign v11 §2,
/// decision 23/10/2026, SPEC 0182).
final initialThemeChoiceProvider = Provider<AppThemeChoice?>((ref) => null);

/// The app's theme choice, as the user chose it in Settings: Claro, Escuro or
/// Modo Sol, or `null` to follow the system (SPEC 0107, SPEC 0182). Modo Sol
/// is reached only through [select]; it is never the default.
final themeChoiceProvider = NotifierProvider<ThemeChoiceController,
    AppThemeChoice?>(ThemeChoiceController.new);

class ThemeChoiceController extends Notifier<AppThemeChoice?> {
  @override
  AppThemeChoice? build() => ref.read(initialThemeChoiceProvider);

  /// Applies [choice] at once, then persists it and hands its [nightModeFor]
  /// to the platform.
  Future<void> select(AppThemeChoice choice) async {
    state = choice;
    await ref.read(appearanceStoreProvider).writeThemeChoice(choice);
    await ref.read(nightModeSyncProvider).apply(nightModeFor(choice));
  }
}

/// The high-contrast choice read before `runApp`, so the first frame is already
/// in it. `main` overrides it with the stored value (SPEC 0130).
final initialHighContrastProvider = Provider<bool>((ref) => false);

/// Whether the user turned on high contrast in Settings (SPEC 0130).
final highContrastProvider =
    NotifierProvider<HighContrastController, bool>(HighContrastController.new);

class HighContrastController extends Notifier<bool> {
  @override
  bool build() => ref.read(initialHighContrastProvider);

  /// Applies [on] at once, then persists it.
  Future<void> select(bool on) async {
    state = on;
    await ref.read(appearanceStoreProvider).writeHighContrast(on);
  }
}

/// The vibration choice read before `runApp` (redesign v11 §3.11). `main`
/// overrides it with the stored value.
final initialVibrationProvider = Provider<bool>((ref) => true);

/// Whether vibration is enabled (redesign v11 §3.11). Bound to
/// [AppHaptics.enabled].
final vibrationProvider =
    NotifierProvider<VibrationController, bool>(VibrationController.new);

class VibrationController extends Notifier<bool> {
  @override
  bool build() {
    final initial = ref.read(initialVibrationProvider);
    AppHaptics.enabled = initial;
    return initial;
  }

  /// Applies [on] at once, persists it, and syncs with [AppHaptics.enabled].
  /// When turning on, fires [AppHaptics.confirm] as a sample (spec §7).
  Future<void> select(bool on) async {
    state = on;
    AppHaptics.enabled = on;
    await ref.read(appearanceStoreProvider).writeVibration(on);
    if (on) await AppHaptics.confirm();
  }
}

/// The reduce-motion choice read before `runApp` (redesign v11 §3.11). `main`
/// overrides it with the stored value.
final initialReduceMotionProvider = Provider<bool>((ref) => false);

/// Whether reduce motion is enabled (redesign v11 §3.11/§6.5).
final reduceMotionProvider =
    NotifierProvider<ReduceMotionController, bool>(ReduceMotionController.new);

class ReduceMotionController extends Notifier<bool> {
  @override
  bool build() {
    final initial = ref.read(initialReduceMotionProvider);
    AppMotion.reduceMotion = initial;
    return initial;
  }

  /// Applies [on] at once, persists it, and syncs with [AppMotion.reduceMotion].
  Future<void> select(bool on) async {
    state = on;
    AppMotion.reduceMotion = on;
    await ref.read(appearanceStoreProvider).writeReduceMotion(on);
  }
}
