// The stored appearance (SPEC 0107, SPEC 0182, SPEC 0184): absent or unknown
// reads as the system base with Sol off, every choice round-trips, a legacy
// choice migrates, and the stored one is handed to the platform at start so
// the next native launch follows it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';

class _FailingStore implements AppearanceStore {
  @override
  Future<ThemeMode> readBaseThemeMode() =>
      Future.error(StateError('corrupt preferences'));

  @override
  Future<void> writeBaseThemeMode(ThemeMode mode) async {}

  @override
  Future<bool> readSunMode() => Future.error(StateError('corrupt preferences'));

  @override
  Future<void> writeSunMode(bool on) async {}

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
  test('the_base_mode_round_trips', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readBaseThemeMode(), ThemeMode.system);

    for (final mode in ThemeMode.values) {
      await store.writeBaseThemeMode(mode);
      expect(await store.readBaseThemeMode(), mode);
    }

    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.baseModeKey: 'sepia'},
    );
    expect(
      await SharedPreferencesAppearanceStore().readBaseThemeMode(),
      ThemeMode.system,
    );
  });

  test('the_sun_mode_round_trips_and_defaults_to_off', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readSunMode(), isFalse);

    await store.writeSunMode(true);
    expect(await store.readSunMode(), isTrue);
    await store.writeSunMode(false);
    expect(await store.readSunMode(), isFalse);
  });

  // An explicit pre-Sol ThemeMode choice (SPEC 0107) carries over as the base
  // theme (SPEC 0184).
  test('an_oldest_legacy_light_or_dark_choice_migrates', () async {
    for (final (legacy, migrated) in [
      ('light', ThemeMode.light),
      ('dark', ThemeMode.dark),
    ]) {
      SharedPreferences.setMockInitialValues(
        {SharedPreferencesAppearanceStore.key: legacy},
      );
      final store = SharedPreferencesAppearanceStore();
      expect(await store.readBaseThemeMode(), migrated, reason: legacy);
      // Persisted under the new key, so a later read no longer depends on
      // the legacy one.
      expect(await store.readBaseThemeMode(), migrated, reason: legacy);
    }
  });

  test('an_oldest_legacy_system_choice_does_not_migrate', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.key: 'system'},
    );
    expect(
      await SharedPreferencesAppearanceStore().readBaseThemeMode(),
      ThemeMode.system,
    );
  });

  // SPEC 0182's choice key: an explicit light/dark choice carries over as the
  // base theme, with Sol left off; a `sun` choice carries over as Sol being on,
  // with the base left at system — Sol used to replace the base choice, and
  // now overrides it instead (SPEC 0184).
  test('a_spec_0182_light_or_dark_choice_migrates_to_the_base', () async {
    for (final (legacy, migrated) in [
      ('light', ThemeMode.light),
      ('dark', ThemeMode.dark),
    ]) {
      SharedPreferences.setMockInitialValues(
        {SharedPreferencesAppearanceStore.choiceKey: legacy},
      );
      final store = SharedPreferencesAppearanceStore();
      expect(await store.readBaseThemeMode(), migrated, reason: legacy);
      expect(await store.readSunMode(), isFalse, reason: legacy);
    }
  });

  test('a_spec_0182_sun_choice_migrates_to_sun_mode_with_a_system_base',
      () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.choiceKey: 'sun'},
    );
    final store = SharedPreferencesAppearanceStore();

    expect(await store.readSunMode(), isTrue);
    expect(await store.readBaseThemeMode(), ThemeMode.system);
  });

  // The migration writes the new keys, not just an in-memory fallback: a
  // store wiped of the legacy key still returns the migrated values.
  test('a_spec_0182_choice_migration_writes_the_new_keys', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.choiceKey: 'sun'},
    );
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readSunMode(), isTrue);
    expect(await store.readBaseThemeMode(), ThemeMode.system);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SharedPreferencesAppearanceStore.sunModeKey), isTrue);
    expect(
      prefs.getString(SharedPreferencesAppearanceStore.baseModeKey),
      'system',
    );
    await prefs.remove(SharedPreferencesAppearanceStore.choiceKey);
    expect(await store.readSunMode(), isTrue);
    expect(await store.readBaseThemeMode(), ThemeMode.system);
  });

  test('the_stored_appearance_is_reapplied_at_start', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.baseModeKey: 'dark'},
    );
    final sync = _RecordingSync();

    final (base, sun) =
        await restoreAppearance(SharedPreferencesAppearanceStore(), sync);

    expect(base, ThemeMode.dark);
    expect(sun, isFalse);
    expect(sync.applied, [ThemeMode.dark]);
  });

  // Sol hands the platform a light night mode, since it ignores the device's
  // own brightness (redesign v11 §2), even with a dark base underneath.
  test('sol_is_reapplied_at_start_as_light_over_any_base', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppearanceStore.baseModeKey: 'dark',
      SharedPreferencesAppearanceStore.sunModeKey: true,
    });
    final sync = _RecordingSync();

    final (base, sun) =
        await restoreAppearance(SharedPreferencesAppearanceStore(), sync);

    expect(base, ThemeMode.dark);
    expect(sun, isTrue);
    expect(sync.applied, [ThemeMode.light]);
  });

  // Read before runApp, so a failure here would keep the app from opening at
  // all; a theme preference is never worth that.
  test('a_store_that_fails_starts_following_the_system_with_sol_off',
      () async {
    final sync = _RecordingSync();

    final (base, sun) = await restoreAppearance(_FailingStore(), sync);

    expect(base, ThemeMode.system);
    expect(sun, isFalse);
    expect(sync.applied, [ThemeMode.system]);
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
