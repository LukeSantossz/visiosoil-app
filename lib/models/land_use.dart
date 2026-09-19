/// Current land use at the sampling point — the one part of the corpus key the
/// device cannot derive, so the user supplies it with one tap and may decline.
///
/// It is asked at tips-generation time and travels with the request rather than
/// being captured with the photograph and persisted on `SoilRecord`. Persisting
/// it is scientifically tidier — it is a property of the sample, not of the
/// query — but it would change the capture flow the UI/UX terminal is
/// redesigning and add a column to a shared table. Moving it to capture later is
/// a migration plus a request-field change, both small
/// (`docs/architecture/research-agent.md` §5.3).
library;

/// The five values of §5.3. It changes which constraint dominates in a way
/// texture alone cannot express: on the same clayey Cerrado soil, degraded
/// pasture binds on compaction and organic matter while long no-till binds on
/// nutrient stratification and subsurface acidity.
enum LandUse {
  nativeVegetation('native_vegetation'),
  pasture('pasture'),
  annualCrop('annual_crop'),
  perennialOrForest('perennial_or_forest'),
  exposedOrDegraded('exposed_or_degraded');

  const LandUse(this.wireName);

  /// The value carried in the corpus and in JSON, which is not the Dart
  /// identifier for the multi-word members.
  final String wireName;

  /// Parses [wireName], returning null for an unrecognised value so a corpus
  /// that adds one does not break a client that predates it.
  static LandUse? fromWire(String? value) {
    if (value == null) return null;
    for (final landUse in values) {
      if (landUse.wireName == value) return landUse;
    }
    return null;
  }
}
