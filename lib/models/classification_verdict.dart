import 'class_score.dart';

/// What a classification run is entitled to assert, derived from the shape of
/// the distribution rather than from the top-1 probability alone.
///
/// With five classes, chance is 0.20, so a top-1 of 0.55 means one thing when
/// the runner-up holds 0.50 and another when it holds 0.12. A single absolute
/// threshold cannot separate those; the margin between the first two candidates
/// is the quantity that does. Recorded as ADR 0011.
///
/// No widget reads this type yet. It ships ahead of the result surface
/// deliberately, so the contract is not held hostage to copy review — roadmap
/// item 2 migrates the UI and retires `ConfidenceLevel`.
enum ClassificationVerdict {
  /// One class leads clearly enough to be named.
  conclusive,

  /// Two classes are too close to separate, but between them they hold enough
  /// of the mass to be worth showing as a pair.
  ambiguous,

  /// The distribution settled nothing worth asserting.
  insufficient,

  /// There is no result to judge.
  ///
  /// Derived from `InferenceService.classify` returning `null`, which today
  /// collapses six distinct causes — missing model asset, isolate spawn
  /// failure, timeout, decode failure, class-count mismatch, inference error.
  /// This member inherits that conflation: it cannot tell a feature that was
  /// never available from a run that failed. Until issue #79 splits the causes,
  /// a result surface must not offer retry on this member, because it cannot
  /// know whether there is anything to retry.
  notAnalysed;

  /// Minimum gap between the first two candidates for [conclusive].
  ///
  /// Provisional. No validation set exists to calibrate against, so this is an
  /// engineering starting point, not a measured value. Recalibration is a
  /// one-line change here by design.
  static const double conclusiveMarginThreshold = 0.15;

  /// Minimum top-1 share for [conclusive]. Provisional, as above.
  static const double conclusiveTopShareThreshold = 0.50;

  /// Minimum share the top two must hold between them for [ambiguous].
  ///
  /// The pair share, rather than the top-1 alone, is what separates a near-tie
  /// worth showing (0.44 / 0.39, pair 0.83, the rest noise) from a distribution
  /// that settled nothing (0.25 / 0.24, pair 0.49, three classes still in
  /// contention). Provisional, as above.
  static const double ambiguousPairShareThreshold = 0.65;

  /// Judges a distribution ordered highest probability first.
  ///
  /// Pure: no model, isolate, or asset is required to evaluate it. A null or
  /// empty [distribution] is [notAnalysed]; a single-entry distribution is
  /// judged against a runner-up of zero.
  factory ClassificationVerdict.fromDistribution(
    List<ClassScore>? distribution,
  ) {
    if (distribution == null || distribution.isEmpty) {
      return ClassificationVerdict.notAnalysed;
    }

    final topShare = distribution.first.probability;
    final runnerUpShare =
        distribution.length > 1 ? distribution[1].probability : 0.0;
    final margin = topShare - runnerUpShare;

    if (margin >= conclusiveMarginThreshold &&
        topShare >= conclusiveTopShareThreshold) {
      return ClassificationVerdict.conclusive;
    }
    if (margin < conclusiveMarginThreshold &&
        topShare + runnerUpShare >= ambiguousPairShareThreshold) {
      return ClassificationVerdict.ambiguous;
    }
    return ClassificationVerdict.insufficient;
  }
}
