import 'package:flutter/widgets.dart';

/// Motion tokens mirroring the design system's `tokens/motion.css`.
///
/// Durations describe intent, not decoration: [instant] for press feedback,
/// [fast] for hovers and color transitions, [base] for default UI transitions,
/// [slow] for sheet and card entrances, [reveal] for result reveals and
/// staggered list-ins. Curves follow Material 3 emphasis.
abstract final class AppMotion {
  /// User's reduce-motion preference (redesign v11 §3.11). Set by
  /// [ReduceMotionController] before the first frame.
  static bool reduceMotion = false;

  /// Returns [duration] unless reduced motion is requested (by the user's
  /// preference or the platform's `disableAnimations`), in which case returns
  /// [reducedMotion] (at most 150 ms) — acceptance criterion, redesign v11 §6.5.
  static Duration durationOf(BuildContext context, Duration duration) {
    if (reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      return duration > reducedMotion ? reducedMotion : duration;
    }
    return duration;
  }
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
