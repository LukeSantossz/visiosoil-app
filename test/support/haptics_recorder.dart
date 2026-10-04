import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every haptic the app asks the platform for during [tester]'s test,
/// in order (SPEC 0126). A tiered haptic records its `HapticFeedbackType`
/// name, such as `HapticFeedbackType.selectionClick`; the plain
/// `HapticFeedback.vibrate()`, which Flutter makes for a long press on
/// Android, records `vibrate`.
List<String> recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      calls.add(call.arguments as String? ?? 'vibrate');
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}
