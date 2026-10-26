// Guards the wiring half of the motion_tokens_match_ds criterion: the three
// animation sites must reference AppMotion, not literal Durations/Curves. The
// splash AnimationController and the onboarding imperative `nextPage` are
// unreachable as widget properties in a test (static PermissionService +
// timers, imperative page control), so — per the accepted code-inspection
// precedent (specs 0007/0009/0024) — a source guard prevents silent reverts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Redesign v11's boot "Peneira" (§6.2, SPEC 0193) replaced SPEC 0089's
  // single-fade splash with three AppMotion-driven stages: the mesh's
  // emphasizedDecelerate scale-in, each grain's emphasizedDecelerate fall,
  // and the logo + name's standardDecelerate rise. Duration still respects
  // the reduce motion preference (redesign v11 §6.5).
  test('splash intro is wired to AppMotion (duration + curve)', () {
    final src =
        File('lib/core/features/splash/splash_screen.dart').readAsStringSync();
    expect(src, contains('AppMotion.reducedMotion'));
    expect(src, contains('curve: AppMotion.emphasizedDecelerate'));
    expect(src, contains('curve: AppMotion.standardDecelerate'));
    expect(src, isNot(contains('Curves.easeIn')));
    expect(src, isNot(contains('Curves.easeOutBack')));
  });

  test('onboarding page transition is wired to AppMotion', () {
    final src = File('lib/core/features/onboarding/onboarding_screen.dart')
        .readAsStringSync();
    expect(src, contains('duration: AppMotion.slow'));
    expect(src, contains('curve: AppMotion.standard'));
  });

  // Duration respects reduce motion preference (redesign v11 §6.5).
  test('history thumbnail switch duration is wired to AppMotion', () {
    final src = File('lib/core/features/history/widgets/history_grid.dart')
        .readAsStringSync();
    expect(src, contains('AppMotion.durationOf(context, AppMotion.base)'));
  });
}
