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

  /// Approximate diagram bands for the broad released classes; these are
  /// illustrative regions, never measured sample coordinates.
  static SoilTextureRegion? regionForClass(String textureClass) =>
      switch (textureClass) {
        'Arenosa' => SoilTextureRegion.sand,
        'Media' => SoilTextureRegion.medium,
        'Argilosa' => SoilTextureRegion.clay,
        'Muito Argilosa' => SoilTextureRegion.veryClay,
        'Siltosa' => SoilTextureRegion.silt,
        _ => null,
      };

  /// The class the onboarding's triangle marks, as PNG 06 draws it
  /// (SPEC 0206): an illustration, not a classification.
  static const exampleClass = 'Media';

  /// USDA reference vocabulary for the collection, independent of model labels.
  static const referenceClasses = <String, Color>{
    'Areia': AppColors.soilSandy,
    'Areia franca': AppColors.soilSandy,
    'Franco-arenosa': AppColors.soilSandy,
    'Franca': AppColors.soilMedium,
    'Franco-siltosa': AppColors.soilSilt,
    'Silte': AppColors.soilSilt,
    'Franco-argilo-arenosa': AppColors.soilClay,
    'Franco-argilosa': AppColors.soilClay,
    'Franco-argilo-siltosa': AppColors.soilClay,
    'Argilo-arenosa': AppColors.soilClay,
    'Argilo-siltosa': AppColors.soilClay,
    'Argila': AppColors.soilClay,
  };

  /// Returns the designated color for a texture class name.
  /// Falls back to [AppColors.outline] for unknown classes.
  static Color forClass(String textureClass) {
    return _colorMap[textureClass] ??
        referenceClasses[textureClass] ??
        AppColors.outline;
  }
}

/// Approximate bands in the illustrative texture diagram.
enum SoilTextureRegion { sand, medium, clay, veryClay, silt }
