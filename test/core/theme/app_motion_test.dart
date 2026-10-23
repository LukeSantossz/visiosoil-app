import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';

void main() {
  setUp(() {
    AppMotion.reduceMotion = false;
  });
  test('AppMotion durations mirror the design-system motion scale', () {
    expect(AppMotion.instant, const Duration(milliseconds: 90));
    expect(AppMotion.fast, const Duration(milliseconds: 140));
    expect(AppMotion.base, const Duration(milliseconds: 220));
    expect(AppMotion.slow, const Duration(milliseconds: 380));
    expect(AppMotion.reveal, const Duration(milliseconds: 640));
  });

  test('AppMotion M3 curves per redesign v11 section 6.1', () {
    expect(AppMotion.standard, const Cubic(0.2, 0, 0, 1));
    // emphasized is M3: Cubic(.2, 0, 0, 1) — same as standard (decision 14.4)
    expect(AppMotion.emphasized, const Cubic(0.2, 0, 0, 1));
    expect(AppMotion.emphasizedDecelerate, const Cubic(0.05, 0.7, 0.1, 1));
    expect(AppMotion.emphasizedAccelerate, const Cubic(0.3, 0, 0.8, 0.15));
    expect(AppMotion.standardDecelerate, const Cubic(0, 0, 0, 1));
    expect(AppMotion.standardAccelerate, const Cubic(0.3, 0, 1, 1));
    // legacy out curve remains for compatibility
    expect(AppMotion.out, const Cubic(0, 0, 0.2, 1));
  });

  test('reduced motion duration is at most 150 ms (acceptance criterion)', () {
    expect(AppMotion.reducedMotion.inMilliseconds, lessThanOrEqualTo(150));
  });

  testWidgets('durationOf returns reduced motion when platform disables animations',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (context) {
          expect(AppMotion.durationOf(context, AppMotion.slow), AppMotion.reducedMotion);
          expect(AppMotion.durationOf(context, AppMotion.fast), AppMotion.fast);
          return const SizedBox();
        }),
      ),
    );
  });

  testWidgets('durationOf returns reduced motion when user preference is on',
      (tester) async {
    AppMotion.reduceMotion = true;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(builder: (context) {
          expect(AppMotion.durationOf(context, AppMotion.slow), AppMotion.reducedMotion);
          expect(AppMotion.durationOf(context, AppMotion.fast), AppMotion.fast);
          return const SizedBox();
        }),
      ),
    );
  });

  testWidgets('durationOf returns full duration when neither signal is set',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(builder: (context) {
          expect(AppMotion.durationOf(context, AppMotion.slow), AppMotion.slow);
          expect(AppMotion.durationOf(context, AppMotion.reveal), AppMotion.reveal);
          return const SizedBox();
        }),
      ),
    );
  });

  // Acceptance criterion: with disableAnimations, no animation exceeds 150 ms.
  testWidgets('no duration exceeds 150 ms with disableAnimations',
      (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (context) {
          for (final duration in [
            AppMotion.instant,
            AppMotion.fast,
            AppMotion.base,
            AppMotion.slow,
            AppMotion.reveal,
          ]) {
            final effective = AppMotion.durationOf(context, duration);
            expect(
              effective.inMilliseconds,
              lessThanOrEqualTo(150),
              reason: 'duration $duration should be capped at 150 ms',
            );
          }
          return const SizedBox();
        }),
      ),
    );
  });

  // Acceptance criterion: with reduce motion preference, no animation exceeds 150 ms.
  testWidgets('no duration exceeds 150 ms with reduce motion preference',
      (tester) async {
    AppMotion.reduceMotion = true;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(builder: (context) {
          for (final duration in [
            AppMotion.instant,
            AppMotion.fast,
            AppMotion.base,
            AppMotion.slow,
            AppMotion.reveal,
          ]) {
            final effective = AppMotion.durationOf(context, duration);
            expect(
              effective.inMilliseconds,
              lessThanOrEqualTo(150),
              reason: 'duration $duration should be capped at 150 ms',
            );
          }
          return const SizedBox();
        }),
      ),
    );
  });
}
