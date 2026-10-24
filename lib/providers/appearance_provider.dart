import 'package:flutter/material.dart';
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

/// The base theme read before `runApp`, so the first frame is already in it.
/// `main` overrides it with the stored value: Sistema, Claro or Escuro,
/// applied unless Modo Sol overrides it (redesign v11 §2, §3.11, SPEC 0186).
final initialBaseThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// The app's base theme choice, as the user chose it in Settings: Sistema,
/// Claro or Escuro (SPEC 0107, SPEC 0186). Independent of [sunModeProvider]:
/// turning Modo Sol off returns to whichever base is held here.
final baseThemeModeProvider = NotifierProvider<BaseThemeModeController,
    ThemeMode>(BaseThemeModeController.new);

class BaseThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialBaseThemeModeProvider);

  /// Applies [mode] at once, then persists it and hands the combined
  /// [nightModeFor] (with the current Sol state) to the platform.
  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(appearanceStoreProvider).writeBaseThemeMode(mode);
    final sun = ref.read(sunModeProvider);
    await ref.read(nightModeSyncProvider).apply(nightModeFor(mode, sun: sun));
  }
}

/// The Modo Sol override read before `runApp`, so the first frame is already
/// in it. `main` overrides it with the stored value (redesign v11 §2,
/// SPEC 0186). `false` by default: Sol is reached only through [select].
final initialSunModeProvider = Provider<bool>((ref) => false);

/// Whether Modo Sol overrides [baseThemeModeProvider] with its own fixed
/// high-contrast light theme (redesign v11 §2, §3.11, SPEC 0186).
final sunModeProvider =
    NotifierProvider<SunModeController, bool>(SunModeController.new);

class SunModeController extends Notifier<bool> {
  @override
  bool build() => ref.read(initialSunModeProvider);

  /// Applies [on] at once, then persists it and hands the combined
  /// [nightModeFor] (with the current base theme) to the platform.
  Future<void> select(bool on) async {
    state = on;
    await ref.read(appearanceStoreProvider).writeSunMode(on);
    final base = ref.read(baseThemeModeProvider);
    await ref.read(nightModeSyncProvider).apply(nightModeFor(base, sun: on));
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
