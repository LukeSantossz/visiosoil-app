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

  /// Whether [value] is a probability: finite, and within the closed unit
  /// interval. The bounds are inclusive, because a one-hot output is what a
  /// confident model is meant to emit.
  ///
  /// Declared once here rather than in each caller because both boundaries
  /// that validate probabilities — the tensor reader and the verdict factory —
  /// have to agree on what one is, and a duplicated rule is how the label
  /// order diverged in the first place.
  ///
  /// This is a check on a single value, not on a set of them. Values that are
  /// each valid can still sum to anything, so this does not establish that a
  /// list of them is a probability distribution; detecting that belongs with
  /// calibration and the `spec.json` contract.
  static bool isProbability(double value) =>
      value.isFinite && value >= 0.0 && value <= 1.0;

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
