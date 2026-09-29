/// What a classification concluded, and why when it failed (ADR 0015,
/// SPEC 0078).
///
/// `classify` used to return `null` for every failure, so the app could not tell
/// a contract that was never shipped from a run that timed out. A report always
/// carries an outcome, and a failed one always carries a named cause.
library;

import 'inference_service.dart';

/// What a classification concluded.
enum ClassificationOutcome {
  ok,

  /// The reserved not-soil signal. Declared and not produced: whether it comes
  /// from a trained negative class or from the quality gate is open (ADR 0015).
  rejectedOod,

  failed,
}

/// Why a classification failed, grouped by what the reader can do about it.
///
/// The order is ADR 0015's current table, column by column: the one under its
/// 2026-09-29 amendment (SPEC 0083).
enum ClassificationFailureCause {
  // Nothing to do: the build is wrong.
  contractMissing,
  contractMalformed,

  /// Nothing in this build measures scale. Retired by the A4-sheet reader.
  measurementUnavailable,

  // Retry, or retake the photograph.
  timeout,
  computationError,
  isolateFailure,
  imageMissing,
  imageUndecodable,
  photographTooCoarse,
  soilRegionTooSmall,
  soilRegionOutsideFrame,

  // Re-release the contract.
  contractUnsupported,
  outputInvalid,
}

/// An outcome with its result or its cause — the enum-plus-payload shape of
/// SPEC 0030's `ImageQualityReport`.
class ClassificationReport {
  const ClassificationReport.ok(InferenceResult this.result)
      : outcome = ClassificationOutcome.ok,
        cause = null;

  const ClassificationReport.failed(ClassificationFailureCause this.cause)
      : outcome = ClassificationOutcome.failed,
        result = null;

  final ClassificationOutcome outcome;

  /// Set only when [outcome] is [ClassificationOutcome.ok].
  final InferenceResult? result;

  /// Set only when [outcome] is [ClassificationOutcome.failed].
  final ClassificationFailureCause? cause;
}
