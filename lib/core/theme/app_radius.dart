import 'package:flutter/material.dart';

/// Constantes de border radius para consistência visual.
abstract final class AppRadius {
  /// 8.0
  static const double sm = 8.0;

  /// 12.0
  static const double md = 12.0;

  /// 16.0
  static const double lg = 16.0;

  /// 24.0
  static const double xl = 24.0;

  /// 999.0 (pill shape)
  static const double pill = 999.0;

  // Pre-built BorderRadius for convenience
  static final BorderRadius borderRadiusSm = BorderRadius.circular(sm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(md);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(lg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(xl);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(pill);
}
