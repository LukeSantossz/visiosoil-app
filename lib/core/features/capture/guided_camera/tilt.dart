import 'dart:math' as math;
import 'dart:ui';

/// Below this magnitude, in m/s², a sample carries no usable gravity: the
/// phone is in free fall, or the sensor reported nothing (SPEC 0165).
const double minGravityMagnitude = 1.0;

/// The unsigned angle, in degrees, between the phone's z axis and the
/// vertical: 0° flat, screen up or down, and 90° on edge. Null for a sample
/// that carries no usable gravity.
double? tiltDegrees(double x, double y, double z) {
  if (!x.isFinite || !y.isFinite || !z.isFinite) return null;
  final magnitude = math.sqrt(x * x + y * y + z * z);
  if (magnitude < minGravityMagnitude) return null;
  final cosine = (z.abs() / magnitude).clamp(0.0, 1.0);
  return math.acos(cosine) * 180 / math.pi;
}

/// The tilt smoothed by an exponential moving average, so the level does not
/// shake, and the direction the phone leans toward, for the level's dot.
class TiltSmoother {
  TiltSmoother({this.alpha = 0.2});

  final double alpha;

  double? _value;
  Offset _direction = Offset.zero;

  /// The smoothed tilt in degrees, or null before the first valid sample.
  double? get value => _value;

  /// The unit vector of the last valid sample's x and y, or zero when it had
  /// none.
  Offset get direction => _direction;

  /// Folds one accelerometer sample in and returns the smoothed tilt. A
  /// sample [tiltDegrees] rejects leaves everything unchanged.
  double? add(double x, double y, double z) {
    final angle = tiltDegrees(x, y, z);
    if (angle == null) return _value;
    final planar = math.sqrt(x * x + y * y);
    _direction = planar == 0 ? Offset.zero : Offset(x / planar, y / planar);
    final previous = _value;
    _value = previous == null ? angle : previous + alpha * (angle - previous);
    return _value;
  }
}
