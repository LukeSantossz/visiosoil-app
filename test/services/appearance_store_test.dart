// The stored theme choice (SPEC 0107): absent or unknown reads as the system's,
// every mode round-trips, and the stored one is handed to the platform at start
// so the next native launch follows it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';

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
}
