import 'package:flutter/material.dart';
import '../../models/soil_texture_labels.dart';
import 'app_colors.dart';

/// Maps soil texture class names to their designated colors.
/// Based on design tokens: earthy tones calibrated per class.
abstract final class SoilTextureColors {
  /// Keyed by name, so this map's own iteration order carries no meaning.
  /// [all] is what defines the order, and it takes it from
  /// [SoilTextureLabels.ordered].
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
  ///
  /// Derived from [SoilTextureLabels.ordered] rather than from `_colorMap`'s
  /// literal order, which listed Siltosa before Media and so contradicted the
  /// model while this getter claimed to match it.
  static List<MapEntry<String, Color>> get all => [
        for (final label in SoilTextureLabels.ordered)
          MapEntry(label, forClass(label)),
      ];
}
