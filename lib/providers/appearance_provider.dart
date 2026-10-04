import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';

/// Where the theme choice is persisted. Overridden with a fake in tests.
final appearanceStoreProvider = Provider<AppearanceStore>(
  (ref) => SharedPreferencesAppearanceStore(),
);

/// How the theme choice reaches the platform's launch. Overridden in tests.
final nightModeSyncProvider = Provider<NightModeSync>(
  (ref) => defaultNightModeSync(),
);

/// The choice read before `runApp`, so the first frame is already in it.
/// `main` overrides it with the stored value.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// The app's theme mode, as the user chose it in Settings (SPEC 0107).
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  /// Applies [mode] at once, then persists it and hands it to the platform.
  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(appearanceStoreProvider).write(mode);
    await ref.read(nightModeSyncProvider).apply(mode);
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
