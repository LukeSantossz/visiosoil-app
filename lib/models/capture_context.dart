/// Contexto de captura com informações do lote, cultura e profundidade.
///
/// Usado para associar metadados à análise de solo antes da captura.
/// Todos os campos são opcionais para permitir flexibilidade no fluxo.
class CaptureContext {
  final Lot? lot;
  final Crop? crop;
  final PlantingSeason? plantingSeason;
  final SamplingDepth? samplingDepth;

  const CaptureContext({
    this.lot,
    this.crop,
    this.plantingSeason,
    this.samplingDepth,
  });

  CaptureContext copyWith({
    Lot? lot,
    Crop? crop,
    PlantingSeason? plantingSeason,
    SamplingDepth? samplingDepth,
  }) {
    return CaptureContext(
      lot: lot ?? this.lot,
      crop: crop ?? this.crop,
      plantingSeason: plantingSeason ?? this.plantingSeason,
      samplingDepth: samplingDepth ?? this.samplingDepth,
    );
  }

  /// Verifica se o contexto está completo para captura.
  bool get isComplete =>
      lot != null && crop != null && plantingSeason != null && samplingDepth != null;

  /// Retorna um resumo do contexto para exibição.
  String get summary {
    final parts = <String>[];
    if (lot != null) parts.add(lot!.name);
    if (crop != null) parts.add(crop!.name);
    if (samplingDepth != null) parts.add(samplingDepth!.label);
    return parts.join(' • ');
  }
}

/// Representa um lote/talhão da propriedade.
class Lot {
  final String id;
  final String name;
  final double? areHectares;

  const Lot({
    required this.id,
    required this.name,
    this.areHectares,
  });

  /// Lotes mock para desenvolvimento.
  static const List<Lot> mockLots = [
    Lot(id: '1', name: 'Lote Norte', areHectares: 45.0),
    Lot(id: '2', name: 'Lote Sul', areHectares: 38.5),
    Lot(id: '3', name: 'Lote Leste', areHectares: 52.0),
    Lot(id: '4', name: 'Pivô Central', areHectares: 120.0),
  ];
}

/// Representa uma cultura agrícola.
class Crop {
  final String id;
  final String name;
  final String icon;

  const Crop({
    required this.id,
    required this.name,
    required this.icon,
  });

  /// Culturas disponíveis.
  static const List<Crop> available = [
    Crop(id: 'soy', name: 'Soja', icon: '🌱'),
    Crop(id: 'corn', name: 'Milho', icon: '🌽'),
    Crop(id: 'cotton', name: 'Algodão', icon: '☁️'),
    Crop(id: 'sugarcane', name: 'Cana', icon: '🎋'),
    Crop(id: 'coffee', name: 'Café', icon: '☕'),
    Crop(id: 'other', name: 'Outra', icon: '🌾'),
  ];
}

/// Época de plantio da cultura.
enum PlantingSeason {
  safra('Safra', 'Plantio principal'),
  safrinha('Safrinha', 'Segunda safra'),
  offSeason('Entressafra', 'Período de descanso');

  final String label;
  final String description;

  const PlantingSeason(this.label, this.description);
}

/// Profundidade de amostragem do solo.
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
