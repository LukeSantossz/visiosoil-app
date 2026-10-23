import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's explicit theme choice (redesign v11 §2, §3.11, SPEC 0182):
/// Claro, Escuro or Modo Sol. There is no "system" member here because
/// following the system is the absence of a choice (see [AppearanceStore.
/// readThemeChoice]), not one of the three the Settings selector offers.
enum AppThemeChoice { light, dark, sun }

/// The [ThemeMode] that hands [choice] to the platform's night-mode channel:
/// light/dark unchanged, and sun forces light since it ignores
/// `platformBrightness` (redesign v11 §2). `null` (no explicit choice) follows
/// the system.
ThemeMode nightModeFor(AppThemeChoice? choice) => switch (choice) {
      AppThemeChoice.light => ThemeMode.light,
      AppThemeChoice.dark => ThemeMode.dark,
      AppThemeChoice.sun => ThemeMode.light,
      null => ThemeMode.system,
    };

/// Persists the user's theme choice (SPEC 0107, SPEC 0182). Behind an
/// interface so it can be faked in tests.
abstract interface class AppearanceStore {
  /// The stored explicit choice, or `null` when none was made (or an unknown
  /// value is stored), meaning the app follows the system brightness
  /// (redesign v11 §2, decision 23/10/2026).
  Future<AppThemeChoice?> readThemeChoice();

  Future<void> writeThemeChoice(AppThemeChoice choice);

  /// Whether high contrast is on (SPEC 0130); `false` when nothing is stored.
  Future<bool> readHighContrast();

  Future<void> writeHighContrast(bool on);

  /// Whether vibration is on (redesign v11 §3.11); `true` when nothing is
  /// stored (enabled by default).
  Future<bool> readVibration();

  Future<void> writeVibration(bool on);

  /// Whether reduce motion is on (redesign v11 §3.11); `false` when nothing is
  /// stored (follows system by default).
  Future<bool> readReduceMotion();

  Future<void> writeReduceMotion(bool on);
}

/// [AppearanceStore] backed by `shared_preferences`, storing the choice's name.
class SharedPreferencesAppearanceStore implements AppearanceStore {
  /// Legacy key (SPEC 0107): the pre-Sol choice, one of [ThemeMode]'s names.
  /// Read only to migrate an explicit `light`/`dark` into [choiceKey]
  /// (SPEC 0182); `system` carried no explicit choice and still does not.
  static const key = 'appearance.themeMode';
  static const choiceKey = 'appearance.themeChoice';
  static const highContrastKey = 'appearance.highContrast';
  static const vibrationKey = 'appearance.vibration';
  static const reduceMotionKey = 'appearance.reduceMotion';

  @override
  Future<AppThemeChoice?> readThemeChoice() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(choiceKey);
    if (stored != null) {
      for (final choice in AppThemeChoice.values) {
        if (choice.name == stored) return choice;
      }
      return null;
    }
    // One-time migration (SPEC 0182): an explicit light/dark choice made
    // before Sol existed carries over; `system` (or nothing stored) still
    // means no explicit choice.
    final legacy = prefs.getString(key);
    final migrated = switch (legacy) {
      'light' => AppThemeChoice.light,
      'dark' => AppThemeChoice.dark,
      _ => null,
    };
    if (migrated != null) await writeThemeChoice(migrated);
    return migrated;
  }

  @override
  Future<void> writeThemeChoice(AppThemeChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(choiceKey, choice.name);
  }

  @override
  Future<bool> readHighContrast() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(highContrastKey) ?? false;
  }

  @override
  Future<void> writeHighContrast(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(highContrastKey, on);
  }

  @override
  Future<bool> readVibration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(vibrationKey) ?? true;
  }

  @override
  Future<void> writeVibration(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(vibrationKey, on);
  }

  @override
  Future<bool> readReduceMotion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(reduceMotionKey) ?? false;
  }

  @override
  Future<void> writeReduceMotion(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(reduceMotionKey, on);
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

/// Reads the stored theme choice and hands its [nightModeFor] to the platform
/// again, so a launch whose override was lost still follows the choice the
/// next time.
///
/// `main` calls this before `runApp`, so a store that cannot be read falls
/// back to `null` (follow the system) rather than keeping the app from
/// opening (SPEC 0182).
Future<AppThemeChoice?> restoreThemeChoice(
  AppearanceStore store,
  NightModeSync sync,
) async {
  AppThemeChoice? choice;
  try {
    choice = await store.readThemeChoice();
  } catch (_) {
    choice = null;
  }
  await sync.apply(nightModeFor(choice));
  return choice;
}

/// Reads the stored high-contrast choice before `runApp` (SPEC 0130). A store
/// that cannot be read leaves it off rather than keeping the app from opening.
Future<bool> restoreHighContrast(AppearanceStore store) async {
  try {
    return await store.readHighContrast();
  } catch (_) {
    return false;
  }
}

/// Reads the stored vibration choice before `runApp` (redesign v11 §3.11). A
/// store that cannot be read leaves it on rather than keeping the app from
/// opening.
Future<bool> restoreVibration(AppearanceStore store) async {
  try {
    return await store.readVibration();
  } catch (_) {
    return true;
  }
}

/// Reads the stored reduce-motion choice before `runApp` (redesign v11 §3.11).
/// A store that cannot be read leaves it off rather than keeping the app from
/// opening.
Future<bool> restoreReduceMotion(AppearanceStore store) async {
  try {
    return await store.readReduceMotion();
  } catch (_) {
    return false;
  }
}
