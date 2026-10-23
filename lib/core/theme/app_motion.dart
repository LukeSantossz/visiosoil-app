import 'package:flutter/animation.dart';

/// Motion tokens mirroring the design system's `tokens/motion.css`.
///
/// Durations describe intent, not decoration: [instant] for press feedback,
/// [fast] for hovers and color transitions, [base] for default UI transitions,
/// [slow] for sheet and card entrances, [reveal] for result reveals and
/// staggered list-ins. Curves follow Material 3 emphasis.
abstract final class AppMotion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 380);
  static const Duration reveal = Duration(milliseconds: 640);

  /// When reduced motion is enabled, animations use this duration or a fade
  /// of at most 150 ms (redesign v11 §6.5 acceptance criterion).
  static const Duration reducedMotion = Duration(milliseconds: 150);

  static const Curve standard = Cubic(0.2, 0, 0, 1);

  /// M3 emphasized curve (redesign v11 §6.1, decision 14.4).
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);

  /// M3 emphasized decelerate: for entrances (redesign v11 §6.1).
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);

  /// M3 emphasized accelerate: for exits (redesign v11 §6.1).
  static const Curve emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);

  /// M3 standard decelerate (redesign v11 §6.1).
  static const Curve standardDecelerate = Cubic(0, 0, 0, 1);

  /// M3 standard accelerate (redesign v11 §6.1).
  static const Curve standardAccelerate = Cubic(0.3, 0, 1, 1);

  /// Legacy out curve for compatibility.
  static const Curve out = Cubic(0, 0, 0.2, 1);
}
