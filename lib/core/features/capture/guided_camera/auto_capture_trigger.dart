import 'dart:math' as math;

import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';

/// Decides when the guided camera takes the photograph itself: once the
/// guidance has been green, still and stable for a second (SPEC 0167).
///
/// It holds no timer. It is fed reading and tilt events, each stamped by the
/// caller's clock, and decides on each one.
class AutoCaptureTrigger {
  /// How long the window must stay qualified before it fires.
  static const window = Duration(milliseconds: 1000);

  /// The smoothed tilt may move less than this across the window, in degrees.
  static const maxTiltSpanDegrees = 1.0;

  /// Consecutive readings' discs may differ by less than this, in mm.
  static const maxDiscStepMm = 2.0;

  /// The window needs at least this many readings before it fires.
  static const minReadings = 2;

  DateTime? _openedAt;
  double _minTilt = 0;
  double _maxTilt = 0;
  int _readings = 0;
  double? _lastDisc;
  bool _fired = false;
  DateTime? _rearmAfter;

  /// When the open window opened, or null when none is open.
  DateTime? get windowOpenedAt => _openedAt;

  /// Whether the trigger has fired this visit.
  bool get fired => _fired;

  /// A reading event: the banner's [row] after the debounce, the disc's
  /// diameter when measured, the smoothed [tilt] (null: `tiltUnavailable`).
  /// Returns true for the one event that fires.
  bool onReading({
    required GuidanceRow row,
    required double? discDiameterMm,
    required double? tilt,
    required DateTime at,
  }) =>
      _onEvent(row: row, tilt: tilt, at: at, reading: true, disc: discDiameterMm);

  /// A tilt event: the banner's [row] and the smoothed [tilt]. Returns true
  /// for the one event that fires.
  bool onTilt({
    required GuidanceRow row,
    required double? tilt,
    required DateTime at,
  }) =>
      _onEvent(row: row, tilt: tilt, at: at, reading: false, disc: null);

  /// Closes the window: a release, a stop, or a manual shot.
  void close() => _openedAt = null;

  /// A shot failed at [at]: the trigger may fire again, but only on a window
  /// opened by an event stamped after the failure.
  void failedAt(DateTime at) {
    _fired = false;
    _rearmAfter = at;
    close();
  }

  bool _onEvent({
    required GuidanceRow row,
    required double? tilt,
    required DateTime at,
    required bool reading,
    required double? disc,
  }) {
    if (_fired) return false;
    final rearmAfter = _rearmAfter;
    if (rearmAfter != null && !at.isAfter(rearmAfter)) {
      close();
      return false;
    }
    if (row != GuidanceRow.ready || tilt == null) {
      close();
      return false;
    }
    if (_openedAt == null) {
      _open(at, tilt, reading: reading, disc: disc);
      return false;
    }
    _minTilt = math.min(_minTilt, tilt);
    _maxTilt = math.max(_maxTilt, tilt);
    final lastDisc = _lastDisc;
    final discJumped = reading &&
        disc != null &&
        lastDisc != null &&
        (disc - lastDisc).abs() >= maxDiscStepMm;
    if (_maxTilt - _minTilt >= maxTiltSpanDegrees || discJumped) {
      // Not still or not stable: this window ends, and the next one opens
      // here, since this event is itself green.
      _open(at, tilt, reading: reading, disc: disc);
      return false;
    }
    if (reading) {
      _readings++;
      if (disc != null) _lastDisc = disc;
    }
    if (at.difference(_openedAt!) >= window && _readings >= minReadings) {
      _fired = true;
      close();
      return true;
    }
    return false;
  }

  void _open(DateTime at, double tilt, {required bool reading, double? disc}) {
    _openedAt = at;
    _minTilt = tilt;
    _maxTilt = tilt;
    _readings = reading ? 1 : 0;
    _lastDisc = reading ? disc : null;
  }
}
