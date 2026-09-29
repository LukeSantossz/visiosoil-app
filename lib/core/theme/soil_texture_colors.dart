import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Maps soil texture class names to their designated colors.
/// Based on design tokens: earthy tones calibrated per class.
abstract final class SoilTextureColors {
  /// Keyed by name, so this map's own iteration order carries no meaning. The
  /// class list and its order are the shipped contract's (SPEC 0083); these keys
  /// are the one place under `lib/` permitted to name a class, because a colour
  /// is a design token and not model output (SPEC 0035).
  static const Map<String, Color> _colorMap = {
    'Arenosa': AppColors.soilSandy,
    // Retained although the model no longer emits Siltosa (SPEC 0046). ADR 0016
    // excludes it from the *first* model, not from the product, and the archive
    // still holds its three sample groups. This key reaches no caller until a
    // released contract carries the class again.
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
}
