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
  /// Four, not five. ADR 0016 keeps Siltosa out of the first model: it holds
  /// three sample groups against the five that SPEC 0042's k = 5 needs, and its
  /// defining fraction is not resolvable at the archive's measured millimetres
  /// per pixel. The archive still contains those samples; the model does not
  /// emit the class.
  ///
  /// Index 2 means Muito Argilosa from SPEC 0046 onward, and meant Siltosa
  /// before it. Nothing produced under the five-class list is comparable to
  /// anything produced after.
  static const List<String> ordered = [
    'Arenosa',
    'Media',
    'Muito Argilosa',
    'Argilosa',
  ];
}
