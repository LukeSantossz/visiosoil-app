// The stored theme choice (SPEC 0107): absent or unknown reads as the system's,
// every mode round-trips, and the stored one is handed to the platform at start
// so the next native launch follows it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';

class _FailingStore implements AppearanceStore {
  @override
  Future<ThemeMode> read() => Future.error(StateError('corrupt preferences'));

  @override
  Future<void> write(ThemeMode mode) async {}

  @override
  Future<bool> readHighContrast() =>
      Future.error(StateError('corrupt preferences'));

  @override
  Future<void> writeHighContrast(bool on) async {}

  @override
  Future<bool> readVibration() =>
      Future.error(StateError('corrupt preferences'));

  @override
  Future<void> writeVibration(bool on) async {}

  @override
  Future<bool> readReduceMotion() =>
      Future.error(StateError('corrupt preferences'));

  @override
  Future<void> writeReduceMotion(bool on) async {}
}

class _RecordingSync implements NightModeSync {
  final applied = <ThemeMode>[];

  @override
  Future<void> apply(ThemeMode mode) async => applied.add(mode);
}

void main() {
  test('the_choice_round_trips', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppearanceStore();
    expect(await store.read(), ThemeMode.system);

    for (final mode in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
      await store.write(mode);
      expect(await store.read(), mode);
    }

    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.key: 'sepia'},
    );
    expect(await SharedPreferencesAppearanceStore().read(), ThemeMode.system);
  });

  test('the_stored_choice_is_reapplied_at_start', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.key: 'dark'},
    );
    final sync = _RecordingSync();

    final mode =
        await restoreThemeMode(SharedPreferencesAppearanceStore(), sync);

    expect(mode, ThemeMode.dark);
    expect(sync.applied, [ThemeMode.dark]);
  });

  // Read before runApp, so a failure here would keep the app from opening at
  // all; a theme preference is never worth that.
  test('a_store_that_fails_starts_in_the_system_theme', () async {
    final sync = _RecordingSync();

    final mode = await restoreThemeMode(_FailingStore(), sync);

    expect(mode, ThemeMode.system);
    expect(sync.applied, [ThemeMode.system]);
  });

  // The high-contrast choice round-trips, reads as off when absent, and a
  // store that cannot be read leaves it off (SPEC 0130).
  test('the_high_contrast_choice_round_trips', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readHighContrast(), isFalse);

    await store.writeHighContrast(true);
    expect(await store.readHighContrast(), isTrue);
    await store.writeHighContrast(false);
    expect(await store.readHighContrast(), isFalse);
  });

  test('an_unreadable_store_leaves_high_contrast_off', () async {
    expect(await restoreHighContrast(_FailingStore()), isFalse);
  });

  // Vibration round-trips, defaults to true, and a failing store keeps it on
  // (redesign v11 §3.11).
  test('vibration_round_trips_and_defaults_to_on', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readVibration(), isTrue);

    await store.writeVibration(false);
    expect(await store.readVibration(), isFalse);
    await store.writeVibration(true);
    expect(await store.readVibration(), isTrue);
  });

  test('an_unreadable_store_leaves_vibration_on', () async {
    expect(await restoreVibration(_FailingStore()), isTrue);
  });

  // Reduce motion round-trips, defaults to false, and a failing store keeps it
  // off (redesign v11 §3.11).
  test('reduce_motion_round_trips_and_defaults_to_off', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readReduceMotion(), isFalse);

    await store.writeReduceMotion(true);
    expect(await store.readReduceMotion(), isTrue);
    await store.writeReduceMotion(false);
    expect(await store.readReduceMotion(), isFalse);
  });

  test('an_unreadable_store_leaves_reduce_motion_off', () async {
    expect(await restoreReduceMotion(_FailingStore()), isFalse);
  });
}
