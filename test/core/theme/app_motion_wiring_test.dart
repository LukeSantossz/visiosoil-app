// Guards the wiring half of the motion_tokens_match_ds criterion: the three
// animation sites must reference AppMotion, not literal Durations/Curves. The
// splash AnimationController and the onboarding imperative `nextPage` are
// unreachable as widget properties in a test (static PermissionService +
// timers, imperative page control), so — per the accepted code-inspection
// precedent (specs 0007/0009/0024) — a source guard prevents silent reverts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splash intro is wired to AppMotion (duration + both curves)', () {
    final src =
        File('lib/core/features/splash/splash_screen.dart').readAsStringSync();
    expect(src, contains('AppMotion.reveal'));
    expect(src, contains('AppMotion.standard'));
    expect(src, contains('AppMotion.emphasized'));
    expect(src, isNot(contains('Curves.easeIn')));
    expect(src, isNot(contains('Curves.easeOutBack')));
  });

  test('onboarding page transition is wired to AppMotion', () {
    final src = File('lib/core/features/onboarding/onboarding_screen.dart')
        .readAsStringSync();
    expect(src, contains('AppMotion.slow'));
    expect(src, contains('AppMotion.standard'));
  });

  test('history thumbnail switch duration is wired to AppMotion', () {
    final src = File('lib/core/features/history/widgets/history_grid.dart')
        .readAsStringSync();
    expect(src, contains('AppMotion.base'));
  });
}
