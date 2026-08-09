/// One class of the classifier and the probability the model assigned it.
///
/// Carries the label rather than the output index so no call site has to
/// re-derive the index-to-label mapping — the way the label order diverged in
/// the first place.
class ClassScore {
  /// Texture class name, one of `SoilTextureLabels.ordered`.
  final String label;

  /// Probability the model assigned to [label], passed through from the output
  /// tensor without renormalisation.
  final double probability;

  const ClassScore({
    required this.label,
    required this.probability,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClassScore &&
          other.label == label &&
          other.probability == probability;

  @override
  int get hashCode => Object.hash(label, probability);

  @override
  String toString() => 'ClassScore($label, $probability)';
}
