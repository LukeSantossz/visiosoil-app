/// The soil texture class labels, in the order the model emits them.
///
/// Single source for that order. It existed in independent copies before, and
/// two of them disagreed: `SoilTextureColors` listed Siltosa before Media while
/// documenting itself as matching the model, which nothing asserted and nothing
/// consumed. Index `i` here is output index `i` of the classifier.
///
/// This list is the app-side declaration only. Once `spec.json` is a tracked
/// runtime contract, the labels come from the model artifact and this constant
/// becomes the fallback rather than the source (see issue #79).
abstract final class SoilTextureLabels {
  /// Every class, in model output order.
  static const List<String> ordered = [
    'Arenosa',
    'Media',
    'Siltosa',
    'Muito Argilosa',
    'Argilosa',
  ];
}
