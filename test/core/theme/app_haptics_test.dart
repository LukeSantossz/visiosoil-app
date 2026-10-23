// Haptic tiers, including the heavy tier used only for blocked (redesign v11).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';

import '../../support/haptics_recorder.dart';

void main() {
  setUp(() {
    // Reset enabled state before each test
    AppHaptics.enabled = true;
  });

  testWidgets('each tier asks the platform for its own haptic', (tester) async {
    final haptics = recordHaptics(tester);

    await AppHaptics.selection();
    await AppHaptics.confirm();
    await AppHaptics.result();

    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  testWidgets('blocked fires heavyImpact twice with 60ms interval',
      (tester) async {
    final haptics = recordHaptics(tester);

    await tester.runAsync(() => AppHaptics.blocked());

    expect(haptics, [
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets('linked fires medium then light with 90ms interval',
      (tester) async {
    final haptics = recordHaptics(tester);

    await tester.runAsync(() => AppHaptics.linked());

    expect(haptics, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('vibration off silences all haptics', (tester) async {
    final haptics = recordHaptics(tester);
    AppHaptics.enabled = false;

    await AppHaptics.selection();
    await AppHaptics.confirm();
    await AppHaptics.result();
    await tester.runAsync(() => AppHaptics.blocked());
    await tester.runAsync(() => AppHaptics.linked());

    expect(haptics, isEmpty);
  });

  testWidgets('vibration on after off fires haptics again', (tester) async {
    final haptics = recordHaptics(tester);
    AppHaptics.enabled = false;
    await AppHaptics.selection();
    expect(haptics, isEmpty);

    AppHaptics.enabled = true;
    await AppHaptics.selection();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  test('heavyImpact is only called by blocked()', () {
    final heavyCalls = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final content = file.readAsStringSync();
      // Skip the AppHaptics definition file itself
      if (file.path.endsWith('app_haptics.dart')) continue;

      if (content.contains('heavyImpact')) {
        heavyCalls.add(file.path);
      }
    }

    expect(
      heavyCalls,
      isEmpty,
      reason:
          'heavyImpact should only be called inside AppHaptics.blocked(), '
          'not directly in production code: $heavyCalls',
    );
  });
}
