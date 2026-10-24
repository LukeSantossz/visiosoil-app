// The stored theme choice (SPEC 0107, SPEC 0182): absent or unknown reads as
// no explicit choice (follow the system), every choice round-trips, a legacy
// light/dark choice migrates, and the stored one is handed to the platform at
// start so the next native launch follows it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';

class _FailingStore implements AppearanceStore {
  @override
  Future<AppThemeChoice?> readThemeChoice() =>
      Future.error(StateError('corrupt preferences'));

  @override
  Future<void> writeThemeChoice(AppThemeChoice choice) async {}

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
    expect(await store.readThemeChoice(), isNull);

    for (final choice in AppThemeChoice.values) {
      await store.writeThemeChoice(choice);
      expect(await store.readThemeChoice(), choice);
    }

    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.choiceKey: 'sepia'},
    );
    expect(await SharedPreferencesAppearanceStore().readThemeChoice(), isNull);
  });

  // An explicit pre-Sol ThemeMode choice carries over as the equivalent
  // AppThemeChoice (SPEC 0182); "system" carried no explicit choice and still
  // does not.
  test('a_legacy_light_or_dark_choice_migrates', () async {
    for (final (legacy, migrated) in [
      ('light', AppThemeChoice.light),
      ('dark', AppThemeChoice.dark),
    ]) {
      SharedPreferences.setMockInitialValues(
        {SharedPreferencesAppearanceStore.key: legacy},
      );
      final store = SharedPreferencesAppearanceStore();
      expect(await store.readThemeChoice(), migrated, reason: legacy);
      // Persisted under the new key, so a later read no longer depends on
      // the legacy one.
      expect(await store.readThemeChoice(), migrated, reason: legacy);
    }
  });

  // The migration writes the new key, not just an in-memory fallback: a
  // store wiped of the legacy key still returns the migrated choice, because
  // the write already landed under `choiceKey` (SPEC 0182).
  test('a_legacy_choice_migration_writes_the_new_key', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.key: 'dark'},
    );
    final store = SharedPreferencesAppearanceStore();
    expect(await store.readThemeChoice(), AppThemeChoice.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SharedPreferencesAppearanceStore.choiceKey),
      'dark',
    );
    await prefs.remove(SharedPreferencesAppearanceStore.key);
    expect(await store.readThemeChoice(), AppThemeChoice.dark);
  });

  test('a_legacy_system_choice_does_not_migrate', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.key: 'system'},
    );
    expect(
      await SharedPreferencesAppearanceStore().readThemeChoice(),
      isNull,
    );
  });

  test('the_stored_choice_is_reapplied_at_start', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.choiceKey: 'dark'},
    );
    final sync = _RecordingSync();

    final choice =
        await restoreThemeChoice(SharedPreferencesAppearanceStore(), sync);

    expect(choice, AppThemeChoice.dark);
    expect(sync.applied, [ThemeMode.dark]);
  });

  // Sol hands the platform a light night mode, since it ignores the device's
  // own brightness (redesign v11 §2).
  test('sol_is_reapplied_at_start_as_light', () async {
    SharedPreferences.setMockInitialValues(
      {SharedPreferencesAppearanceStore.choiceKey: 'sun'},
    );
    final sync = _RecordingSync();

    final choice =
        await restoreThemeChoice(SharedPreferencesAppearanceStore(), sync);

    expect(choice, AppThemeChoice.sun);
    expect(sync.applied, [ThemeMode.light]);
  });

  // Read before runApp, so a failure here would keep the app from opening at
  // all; a theme preference is never worth that.
  test('a_store_that_fails_starts_following_the_system', () async {
    final sync = _RecordingSync();

    final choice = await restoreThemeChoice(_FailingStore(), sync);

    expect(choice, isNull);
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
