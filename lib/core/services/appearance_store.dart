import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The night mode the platform's launch channel understands, combining the
/// base theme with whether Modo Sol overrides it (redesign v11 §2, §3.11,
/// SPEC 0186): [base] unchanged when Sol is off, and `light` when it is on,
/// since Sol ignores `platformBrightness`.
ThemeMode nightModeFor(ThemeMode base, {required bool sun}) =>
    sun ? ThemeMode.light : base;

/// Persists the user's appearance choices (SPEC 0107, SPEC 0182, SPEC 0186).
/// Behind an interface so it can be faked in tests.
abstract interface class AppearanceStore {
  /// The base theme — Sistema, Claro or Escuro — applied unless Modo Sol
  /// overrides it. [ThemeMode.system] when nothing was ever chosen.
  Future<ThemeMode> readBaseThemeMode();

  Future<void> writeBaseThemeMode(ThemeMode mode);

  /// Whether Modo Sol overrides [readBaseThemeMode] with its own fixed
  /// high-contrast light theme (redesign v11 §2). `false` when nothing is
  /// stored.
  Future<bool> readSunMode();

  Future<void> writeSunMode(bool on);

  /// Whether vibration is on (redesign v11 §3.11); `true` when nothing is
  /// stored (enabled by default).
  Future<bool> readVibration();

  Future<void> writeVibration(bool on);

  /// Whether reduce motion is on (redesign v11 §3.11); `false` when nothing is
  /// stored (follows system by default).
  Future<bool> readReduceMotion();

  Future<void> writeReduceMotion(bool on);
}

/// [AppearanceStore] backed by `shared_preferences`.
class SharedPreferencesAppearanceStore implements AppearanceStore {
  /// Oldest legacy key (SPEC 0107): one of [ThemeMode]'s names, including
  /// `system`. Read only to migrate into [baseModeKey] once that key and
  /// [choiceKey] are both empty.
  static const key = 'appearance.themeMode';

  /// SPEC 0182's key: `light` | `dark` | `sun`, with no separate Sol flag.
  /// Read only to migrate into [baseModeKey] and [sunModeKey] (SPEC 0186): a
  /// legacy `sun` choice becomes `sunMode=true` with the base left at
  /// `system`, since Sol used to replace the base choice rather than
  /// overriding it.
  static const choiceKey = 'appearance.themeChoice';
  static const baseModeKey = 'appearance.baseThemeMode';
  static const sunModeKey = 'appearance.sunMode';
  static const vibrationKey = 'appearance.vibration';
  static const reduceMotionKey = 'appearance.reduceMotion';

  @override
  Future<ThemeMode> readBaseThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(baseModeKey);
    if (stored != null) {
      for (final mode in ThemeMode.values) {
        if (mode.name == stored) return mode;
      }
      return ThemeMode.system;
    }
    final legacyChoice = prefs.getString(choiceKey);
    final migratedFromChoice = switch (legacyChoice) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      // Sol used to be a base choice of its own; it is now an override on
      // top of `system` (SPEC 0186).
      'sun' => ThemeMode.system,
      _ => null,
    };
    if (migratedFromChoice != null) {
      await writeBaseThemeMode(migratedFromChoice);
      return migratedFromChoice;
    }
    final legacyMode = prefs.getString(key);
    final migratedFromMode = switch (legacyMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
    if (migratedFromMode != null) {
      await writeBaseThemeMode(migratedFromMode);
      return migratedFromMode;
    }
    return ThemeMode.system;
  }

  @override
  Future<void> writeBaseThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(baseModeKey, mode.name);
  }

  @override
  Future<bool> readSunMode() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(sunModeKey);
    if (stored != null) return stored;
    if (prefs.getString(choiceKey) == 'sun') {
      await writeSunMode(true);
      return true;
    }
    return false;
  }

  @override
  Future<void> writeSunMode(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sunModeKey, on);
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

/// Reads the stored base theme and Modo Sol override, and hands their
/// combined [nightModeFor] to the platform again, so a launch whose override
/// was lost still follows the choice the next time.
///
/// `main` calls this before `runApp`, so a store that cannot be read falls
/// back to following the system with Sol off, rather than keeping the app
/// from opening (SPEC 0182, SPEC 0186).
Future<(ThemeMode base, bool sun)> restoreAppearance(
  AppearanceStore store,
  NightModeSync sync,
) async {
  ThemeMode base;
  try {
    base = await store.readBaseThemeMode();
  } catch (_) {
    base = ThemeMode.system;
  }
  bool sun;
  try {
    sun = await store.readSunMode();
  } catch (_) {
    sun = false;
  }
  await sync.apply(nightModeFor(base, sun: sun));
  return (base, sun);
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
