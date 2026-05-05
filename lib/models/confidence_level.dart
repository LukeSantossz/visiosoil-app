import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';

/// Faixas de confiança para classificação de textura.
///
/// Thresholds centralizados: alta >= 80%, moderada 60-79%, baixa < 60%.
enum ConfidenceLevel {
  high,
  moderate,
  low;

  /// Threshold inferior da faixa alta (0.80).
  static const double highThreshold = 0.80;

  /// Threshold inferior da faixa moderada (0.60).
  static const double moderateThreshold = 0.60;

  /// Determina o nível de confiança a partir do score (0.0 a 1.0).
  /// Retorna [low] para valores nulos ou NaN.
  factory ConfidenceLevel.fromScore(double? score) {
    if (score == null || score.isNaN) return ConfidenceLevel.low;
    if (score >= highThreshold) return ConfidenceLevel.high;
    if (score >= moderateThreshold) return ConfidenceLevel.moderate;
    return ConfidenceLevel.low;
  }

  /// Label localizado para exibição.
  String get label => switch (this) {
        ConfidenceLevel.high => 'Alta',
        ConfidenceLevel.moderate => 'Moderada',
        ConfidenceLevel.low => 'Baixa',
      };

  /// Cor de fundo do badge.
  Color get backgroundColor => switch (this) {
        ConfidenceLevel.high => AppColors.primaryContainer,
        ConfidenceLevel.moderate => AppColors.warningContainer,
        ConfidenceLevel.low => AppColors.errorContainer,
      };

  /// Cor do texto/ícone do badge.
  Color get foregroundColor => switch (this) {
        ConfidenceLevel.high => AppColors.onPrimaryContainer,
        ConfidenceLevel.moderate => const Color(0xFF6D4C1D),
        ConfidenceLevel.low => AppColors.onErrorContainer,
      };

  /// Ícone representativo do nível.
  IconData get icon => switch (this) {
        ConfidenceLevel.high => Icons.verified,
        ConfidenceLevel.moderate => Icons.info_outline,
        ConfidenceLevel.low => Icons.warning_amber_rounded,
      };
}
