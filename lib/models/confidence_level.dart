import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';

/// Confidence ranges for texture classification.
///
/// Centralized thresholds: high >= 80%, moderate 60-79%, low < 60%.
enum ConfidenceLevel {
  high,
  moderate,
  low;

  /// Lower threshold of the high range (0.80).
  static const double highThreshold = 0.80;

  /// Lower threshold of the moderate range (0.60).
  static const double moderateThreshold = 0.60;

  /// Determines the confidence level from the score (0.0 to 1.0).
  /// Returns [low] for null or NaN values.
  factory ConfidenceLevel.fromScore(double? score) {
    if (score == null || score.isNaN) return ConfidenceLevel.low;
    if (score >= highThreshold) return ConfidenceLevel.high;
    if (score >= moderateThreshold) return ConfidenceLevel.moderate;
    return ConfidenceLevel.low;
  }

  /// Localized label for display.
  String get label => switch (this) {
        ConfidenceLevel.high => 'Alta',
        ConfidenceLevel.moderate => 'Moderada',
        ConfidenceLevel.low => 'Baixa',
      };

  /// Badge background color.
  Color get backgroundColor => switch (this) {
        ConfidenceLevel.high => AppColors.primaryContainer,
        ConfidenceLevel.moderate => AppColors.warningContainer,
        ConfidenceLevel.low => AppColors.errorContainer,
      };

  /// Badge text/icon color.
  Color get foregroundColor => switch (this) {
        ConfidenceLevel.high => AppColors.onPrimaryContainer,
        ConfidenceLevel.moderate => const Color(0xFF6D4C1D),
        ConfidenceLevel.low => AppColors.onErrorContainer,
      };

  /// Icon representing the level.
  IconData get icon => switch (this) {
        ConfidenceLevel.high => Icons.verified,
        ConfidenceLevel.moderate => Icons.info_outline,
        ConfidenceLevel.low => Icons.warning_amber_rounded,
      };
}
