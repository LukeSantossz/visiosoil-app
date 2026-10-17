import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/tilt.dart';

/// A gravity vector tilted [degrees] from the phone's z axis.
({double x, double y, double z}) _atDegrees(double degrees) {
  final radians = degrees * math.pi / 180;
  return (x: 0, y: 9.81 * math.sin(radians), z: 9.81 * math.cos(radians));
}

void main() {
  test('tilt_is_the_angle_to_gravity', () {
    expect(tiltDegrees(0, 0, 9.81), closeTo(0, 0.01));
    // Face down over the sheet reads level, not 180°.
    expect(tiltDegrees(0, 0, -9.81), closeTo(0, 0.01));
    expect(tiltDegrees(0, 9.81, 0), closeTo(90, 0.01));
    for (final degrees in [5.0, 12.0]) {
      final v = _atDegrees(degrees);
      expect(tiltDegrees(v.x, v.y, v.z), closeTo(degrees, 0.01));
    }
    // |z| / |a| can round above 1 for a vertical vector; clamped, never NaN.
    expect(tiltDegrees(0, 1e-9, 9.81), closeTo(0, 0.01));
  });

  test('a_degenerate_sample_is_skipped', () {
    expect(tiltDegrees(0, 0, 0), isNull);
    expect(tiltDegrees(0, 0, 0.5), isNull);
    expect(tiltDegrees(double.nan, 0, 9.81), isNull);
    expect(tiltDegrees(0, double.infinity, 9.81), isNull);

    final smoother = TiltSmoother();
    expect(smoother.add(0, 0, 0), isNull);
    expect(smoother.add(0, 0, 0.5), isNull);
    expect(smoother.value, isNull);

    smoother.add(0, 0, 9.81);
    expect(smoother.add(double.nan, 0, 0), closeTo(0, 1e-9));
  });

  test('tilt_is_smoothed', () {
    final smoother = TiltSmoother();
    for (var i = 0; i < 10; i++) {
      smoother.add(0, 0, 9.81);
    }
    final v = _atDegrees(30);
    expect(smoother.add(v.x, v.y, v.z), closeTo(6, 0.01));
  });

  test('the_direction_points_along_the_last_valid_sample', () {
    final smoother = TiltSmoother();
    expect(smoother.direction, Offset.zero);
    smoother.add(3, 4, 9.81);
    expect(smoother.direction.dx, closeTo(0.6, 1e-9));
    expect(smoother.direction.dy, closeTo(0.8, 1e-9));
    smoother.add(0, 0, 9.81);
    expect(smoother.direction, Offset.zero);
  });
}
