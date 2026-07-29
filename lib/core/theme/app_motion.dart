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

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve emphasized = Cubic(0.3, 0, 0.1, 1);
  static const Curve out = Cubic(0, 0, 0.2, 1);
}
