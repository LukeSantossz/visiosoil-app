import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Maps soil texture class names to their designated colors.
/// Based on design tokens: earthy tones calibrated per class.
abstract final class SoilTextureColors {
  static const Map<String, Color> _colorMap = {
    'Arenosa': AppColors.soilSandy,
    'Siltosa': AppColors.soilSilt,
    'Media': AppColors.soilMedium,
    'Muito Argilosa': AppColors.soilVeryClay,
    'Argilosa': AppColors.soilClay,
  };

  /// Returns the designated color for a texture class name.
  /// Falls back to [AppColors.outline] for unknown classes.
  static Color forClass(String textureClass) {
    return _colorMap[textureClass] ?? AppColors.outline;
  }

  /// All texture class entries in model output order.
  static List<MapEntry<String, Color>> get all => _colorMap.entries.toList();
}
