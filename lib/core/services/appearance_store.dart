import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's theme choice (SPEC 0107). Behind an interface so it can
/// be faked in tests.
abstract interface class AppearanceStore {
  /// The stored choice, or [ThemeMode.system] when none, or an unknown one, is
  /// stored.
  Future<ThemeMode> read();

  Future<void> write(ThemeMode mode);
}

/// [AppearanceStore] backed by `shared_preferences`, storing the mode's name.
class SharedPreferencesAppearanceStore implements AppearanceStore {
  static const key = 'appearance.themeMode';

  @override
  Future<ThemeMode> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.system,
    );
  }

  @override
  Future<void> write(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, mode.name);
  }
}

/// Hands the theme choice to the platform, so the launch it draws before
/// Flutter's first frame follows it (SPEC 0107, #245).
abstract interface class NightModeSync {
  /// Never throws: a launch that cannot follow the choice is no reason to
  /// refuse it.
  Future<void> apply(ThemeMode mode);
}

/// Android's side: `MainActivity` passes the mode's name to
/// `UiModeManager.setApplicationNightMode` on API 31+, which the system splash
/// reads at the next cold launch.
class MethodChannelNightModeSync implements NightModeSync {
  const MethodChannelNightModeSync();

  static const channelName = 'visiosoil/appearance';
  static const method = 'setNightMode';

  @override
  Future<void> apply(ThemeMode mode) async {
    try {
      await const MethodChannel(channelName).invokeMethod<void>(
        method,
        mode.name,
      );
    } on MissingPluginException {
      // No platform side: the launch keeps following the system.
    } on PlatformException {
      // The platform refused: likewise.
    }
  }
}

/// Every other platform: the launch follows the system.
class NoNightModeSync implements NightModeSync {
  const NoNightModeSync();

  @override
  Future<void> apply(ThemeMode mode) async {}
}

/// The platform's [NightModeSync]: the channel on Android, none elsewhere.
NightModeSync defaultNightModeSync() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? const MethodChannelNightModeSync()
        : const NoNightModeSync();

/// Reads the stored choice and hands it to the platform again, so a launch
/// whose override was lost still follows the choice the next time.
///
/// `main` calls this before `runApp`, so a store that cannot be read falls back
/// to [ThemeMode.system] rather than keeping the app from opening.
Future<ThemeMode> restoreThemeMode(
  AppearanceStore store,
  NightModeSync sync,
) async {
  ThemeMode mode;
  try {
    mode = await store.read();
  } catch (_) {
    mode = ThemeMode.system;
  }
  await sync.apply(mode);
  return mode;
}
