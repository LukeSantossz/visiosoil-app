# SPEC: refactor(inference): classify reports an outcome and a named cause, never null

## Problem

`InferenceService.classify` returns `null` for every failure, so the app cannot
tell a model that was never shipped from a run that timed out. ADR 0011 accepted
that debt on one condition: no result surface may offer a retry on `notAnalysed`
until A4 lands. ADR 0015 decided the replacement: an outcome plus one of twelve
named causes, never `null`. This spec implements that half of A4 on the path the
app runs today. The contract of numbers ADR 0024 re-scoped is the second half,
in a later spec.

## Scope

- Includes:
  - `lib/core/services/classification_report.dart`, declaring:
    - `ClassificationOutcome`: `ok`, `rejectedOod`, `failed`;
    - `ClassificationFailureCause`: ADR 0015's twelve causes, in its table's
      order;
    - `ClassificationReport`: an outcome with its `InferenceResult` or its
      cause, and the constructors `.ok(result)` and `.failed(cause)`. This is
      the enum-plus-payload shape of SPEC 0030's `ImageQualityReport`.
  - `InferenceService.initialize` returns `Future<ClassificationFailureCause?>`,
    with `null` meaning ready:
    - an empty asset is `modelEmpty`, and it is remembered, as it is today;
    - a loader that fails on every attempt is `modelMissing`, and a later call
      may still retry, as it does today.
  - `InferenceService.classify` returns `Future<ClassificationReport>`:
    - a failed `initialize` reports its cause;
    - a spawn that throws is `isolateFailure`;
    - an isolate that exits without answering is also `isolateFailure`. The
      isolate's `onExit` is wired to the response port, so a dead worker is
      reported at once instead of after the 15 s timeout;
    - the timeout is `timeout`, and the isolate is still killed.
  - The isolate message becomes the report, so the causes produced inside the
    worker reach the caller:
    - an absent image file is `imageMissing`;
    - an image that does not decode, or throws while decoding, is
      `imageUndecodable`;
    - an interpreter that fails to build or run is `interpreterError`;
    - tensors that disagree with what the app declares are
      `modelContractMismatch`: the input shape `[1, 224, 224, 3]`, a float32
      input and output, and the output class count against
      `SoilTextureLabels.ordered`;
    - a non-probability output is `outputInvalid`.
  - Two `@visibleForTesting` static seams, so each branch is tested against
    the real code rather than a double of it:
    - `checkTensors(...)`, which returns the mismatch cause or `null`;
    - `interpretOutput(probabilities)`, which returns the report for an output
      tensor.
  - `capture_screen.dart` reads the report. `CaptureUiState` gains a nullable
    `classificationFailureCause`, set when the outcome is `failed` and cleared
    by a new capture. `ClassificationStatus` keeps its four members and their
    meaning, and the screen shows exactly what it shows today.
  - The existing tests move to the report. The `capture_screen_test` fake
    returns reports.
- Does NOT include:
  - `spec.json`: its schema, a reader, or the three contract causes as
    produced values. `contractMissing`, `contractMalformed` and
    `contractUnsupported` are declared and have no producer until A4 (2).
  - Reading labels, input size or normalisation from a contract, deleting
    `SoilTextureLabels`, or the sweep for label literals. Those are A4 (2).
  - Any preprocessing change: the centred-square crop, the EXIF bake, or the
    descriptor path's wiring.
  - Producing `rejectedOod`. The member is declared; its producer is open, per
    ADR 0015.
  - Any user-facing string, any screen distinguishing causes, or offering a
    retry. Those are the UI/UX terminal's roadmap item 2.
  - Persisting the outcome or the cause.

## Acceptance Criteria

- `missing_model_asset_yields_model_missing`: a loader that throws on every
  attempt makes `initialize` return `modelMissing`, and `classify` report it
  without spawning.
- `empty_model_asset_yields_model_empty`: an empty asset gives `modelEmpty`, on
  this call and on later calls, without reloading.
- `failed_initialize_returns_the_cause`: `initialize` returns the cause that
  `classify` then reports, and returns `null` once the service is ready.
- `missing_image_file_yields_image_missing`
- `undecodable_image_yields_image_undecodable`
- `interpreter_error_yields_interpreter_error`: model bytes the interpreter
  cannot load, run against a real image file.
- `inference_timeout_yields_timeout`, and the isolate is still killed.
- `isolate_spawn_failure_yields_isolate_failure`: an entry point that cannot be
  sent to an isolate.
- `isolate_death_yields_isolate_failure`: an entry point that throws before
  answering is reported well before the timeout.
- `interpreter_disagreeing_with_the_app_yields_model_contract_mismatch`, checked
  independently for the input shape, the input type, the output type and the
  output class count.
- `non_probability_output_yields_output_invalid`: a non-finite value, or one
  outside the unit interval.
- `successful_run_yields_ok_with_the_distribution`: the distribution and its
  tie-breaking are unchanged.
- `failure_causes_follow_adr_0015`: there are twelve causes, and their names are
  exactly ADR 0015's.
- `capture_screen_renders_a_failed_report_without_a_result`: a failed report
  reaches the failed state the screen renders today, and the state carries its
  cause.
