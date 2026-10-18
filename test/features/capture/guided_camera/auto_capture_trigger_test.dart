import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/auto_capture_trigger.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';

final _t0 = DateTime.utc(2026, 10, 18, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

/// Feeds a steady scene: readings every 333 ms and tilts every 200 ms from
/// [from] to [to] ms, in time order, and returns the instant that fired, if
/// any.
int? _steady(
  AutoCaptureTrigger trigger, {
  int from = 0,
  int to = 2000,
  GuidanceRow row = GuidanceRow.ready,
  double tilt = 2.0,
  double disc = 70,
  double Function(int ms)? tiltAt,
  double Function(int ms)? discAt,
}) {
  final events = <(int, bool)>[
    for (var ms = from; ms <= to; ms += 333) (ms, true),
    for (var ms = from; ms <= to; ms += 200) (ms, false),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : (a.$2 ? 0 : 1));
  for (final (ms, isReading) in events) {
    final t = tiltAt?.call(ms) ?? tilt;
    final fired = isReading
        ? trigger.onReading(
            row: row,
            discDiameterMm: discAt?.call(ms) ?? disc,
            tilt: t,
            at: _at(ms),
          )
        : trigger.onTilt(row: row, tilt: t, at: _at(ms));
    if (fired) return ms;
  }
  return null;
}

void main() {
  test('fires_after_one_steady_green_second', () {
    final trigger = AutoCaptureTrigger();
    final fired = _steady(trigger);
    expect(fired, isNotNull);
    expect(fired, greaterThanOrEqualTo(1000));
    // The first event at or past 1000 ms: the tilt at 1000 ms.
    expect(fired, 1000);
    expect(trigger.fired, isTrue);
  });

  test('one_reading_is_not_enough', () {
    final trigger = AutoCaptureTrigger();
    // One reading opens the window; only tilts follow.
    expect(
      trigger.onReading(
          row: GuidanceRow.ready, discDiameterMm: 70, tilt: 2, at: _at(0)),
      isFalse,
    );
    for (var ms = 200; ms <= 1400; ms += 200) {
      expect(
        trigger.onTilt(row: GuidanceRow.ready, tilt: 2, at: _at(ms)),
        isFalse,
        reason: '$ms ms holds one reading',
      );
    }
    expect(
      trigger.onReading(
          row: GuidanceRow.ready, discDiameterMm: 70, tilt: 2, at: _at(1500)),
      isTrue,
    );
  });

  test('leaving_green_closes_the_window', () {
    final trigger = AutoCaptureTrigger();
    expect(_steady(trigger, to: 700), isNull);
    expect(
      trigger.onReading(
          row: GuidanceRow.smallSoil, discDiameterMm: 47, tilt: 2, at: _at(800)),
      isFalse,
    );
    expect(trigger.windowOpenedAt, isNull);
    final fired = _steady(trigger, from: 1000, to: 3000);
    expect(fired, 2000);
  });

  test('a_moving_phone_does_not_fire', () {
    // Spanning 1.0° closes the window, so nothing fires at 1000 ms.
    final moving = AutoCaptureTrigger();
    expect(
      _steady(moving, to: 1000, tiltAt: (ms) => ms >= 600 ? 3.0 : 2.0),
      isNull,
    );
    // Spanning 0.99° does not.
    final still = AutoCaptureTrigger();
    expect(_steady(still, tiltAt: (ms) => ms >= 600 ? 2.99 : 2.0), 1000);
  });

  test('an_unstable_disc_does_not_fire', () {
    final unstable = AutoCaptureTrigger();
    expect(
      _steady(unstable, to: 1000, discAt: (ms) => ms >= 600 ? 72.0 : 70.0),
      isNull,
    );
    final stable = AutoCaptureTrigger();
    expect(_steady(stable, discAt: (ms) => ms >= 600 ? 71.99 : 70.0), 1000);
  });

  test('fires_once', () {
    final trigger = AutoCaptureTrigger();
    expect(_steady(trigger), 1000);
    expect(_steady(trigger, from: 3000, to: 6000), isNull);
  });

  test('a_failed_shot_rearms_after_a_new_second', () {
    final trigger = AutoCaptureTrigger();
    expect(_steady(trigger, to: 600), isNull);
    trigger.failedAt(_at(650));
    // The window open before the failure does not carry over, and no event
    // stamped at or before the failure opens one.
    expect(trigger.windowOpenedAt, isNull);
    expect(trigger.onTilt(row: GuidanceRow.ready, tilt: 2, at: _at(650)), isFalse);
    expect(trigger.windowOpenedAt, isNull);
    expect(_steady(trigger, from: 700, to: 3000), 1700);
  });

  test('a_fired_trigger_rearms_after_a_failed_shot', () {
    final trigger = AutoCaptureTrigger();
    expect(_steady(trigger), 1000);
    trigger.failedAt(_at(1100));
    expect(trigger.fired, isFalse);
    expect(_steady(trigger, from: 1200, to: 3000), 2200);
  });

  test('no_tilt_no_window', () {
    final trigger = AutoCaptureTrigger();
    for (var ms = 0; ms <= 2000; ms += 100) {
      expect(
        trigger.onReading(
            row: GuidanceRow.ready, discDiameterMm: 70, tilt: null, at: _at(ms)),
        isFalse,
      );
    }
    expect(trigger.windowOpenedAt, isNull);
  });

  test('close_ends_the_window', () {
    final trigger = AutoCaptureTrigger();
    expect(_steady(trigger, to: 600), isNull);
    trigger.close();
    expect(trigger.windowOpenedAt, isNull);
  });
}
