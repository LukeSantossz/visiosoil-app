/// What a classification concluded, and why when it failed (ADR 0015,
/// SPEC 0078).
///
/// `classify` used to return `null` for every failure, so the app could not tell
/// a model that was never shipped from a run that timed out. A report always
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
/// The order is ADR 0015's table, column by column.
enum ClassificationFailureCause {
  // Nothing to do: the build is wrong.
  contractMissing,
  contractMalformed,
  modelMissing,
  modelEmpty,

  // Retrying is the right response.
  timeout,
  interpreterError,
  isolateFailure,
  imageMissing,
  imageUndecodable,

  // Re-export the model.
  contractUnsupported,
  modelContractMismatch,
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
