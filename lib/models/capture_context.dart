/// Capture context with crop, season, and depth information.
///
/// Used to attach metadata to the soil analysis before capture.
/// All fields are optional to allow flexibility in the flow.
class CaptureContext {
  final Crop? crop;
  final PlantingSeason? plantingSeason;
  final SamplingDepth? samplingDepth;

  const CaptureContext({
    this.crop,
    this.plantingSeason,
    this.samplingDepth,
  });

  CaptureContext copyWith({
    Crop? crop,
    PlantingSeason? plantingSeason,
    SamplingDepth? samplingDepth,
  }) {
    return CaptureContext(
      crop: crop ?? this.crop,
      plantingSeason: plantingSeason ?? this.plantingSeason,
      samplingDepth: samplingDepth ?? this.samplingDepth,
    );
  }

  /// Checks whether the context is complete for capture.
  bool get isComplete =>
      crop != null && plantingSeason != null && samplingDepth != null;

  /// Returns a summary of the context for display.
  String get summary {
    final parts = <String>[];
    if (crop != null) parts.add(crop!.name);
    if (samplingDepth != null) parts.add(samplingDepth!.label);
    return parts.join(' • ');
  }
}

/// Represents an agricultural crop.
class Crop {
  final String id;
  final String name;
  final String iconCodePoint;

  const Crop({
    required this.id,
    required this.name,
    required this.iconCodePoint,
  });

  /// Available crops with Material Design icons.
  static const List<Crop> available = [
    Crop(id: 'soy', name: 'Soja', iconCodePoint: 'grass'),
    Crop(id: 'corn', name: 'Milho', iconCodePoint: 'grain'),
    Crop(id: 'cotton', name: 'Algodão', iconCodePoint: 'filter_vintage'),
    Crop(id: 'sugarcane', name: 'Cana', iconCodePoint: 'park'),
    Crop(id: 'coffee', name: 'Café', iconCodePoint: 'local_cafe'),
    Crop(id: 'other', name: 'Outra', iconCodePoint: 'eco'),
  ];
}

/// Planting season of the crop.
enum PlantingSeason {
  safra('Safra', 'Plantio principal'),
  safrinha('Safrinha', 'Segunda safra'),
  offSeason('Entressafra', 'Período de descanso');

  final String label;
  final String description;

  const PlantingSeason(this.label, this.description);
}

/// Soil sampling depth.
enum SamplingDepth {
  shallow(0, 20, '0-20 cm', 'Camada superficial'),
  medium(20, 40, '20-40 cm', 'Camada intermediária'),
  deep(40, 60, '40-60 cm', 'Camada profunda');

  final int minCm;
  final int maxCm;
  final String label;
  final String description;

  const SamplingDepth(this.minCm, this.maxCm, this.label, this.description);
}
