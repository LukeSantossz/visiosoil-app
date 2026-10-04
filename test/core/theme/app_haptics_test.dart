// The three haptic tiers, and the fourth that is never used (SPEC 0126).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';

import '../../support/haptics_recorder.dart';

void main() {
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

  test('never_heavy', () {
    final heavy = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('heavyImpact'))
        .map((file) => file.path)
        .toList();

    expect(heavy, isEmpty);
  });
}
