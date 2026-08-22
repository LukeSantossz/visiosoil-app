# A classification reports an outcome and a named cause, never an absent value

VisioSoil's `InferenceService.classify` returns a report carrying one of three
outcomes — `ok`, `rejectedOod`, `failed` — and, when it failed, one of twelve
named causes. It never returns `null`. The causes are grouped by what the reader
can do about them: rebuild the application, retry the run, or re-export the
model.

## Status

Accepted. Promoted at the Spec Gate for
[`docs/specs/0035-spec-json-runtime-contract.md`](../specs/0035-spec-json-runtime-contract.md),
whose Design Decisions it records. It discharges the debt
[`ADR 0011`](0011-classification-verdict-from-margin-and-mass.md) took on
deliberately: that record shipped `notAnalysed` derived from a `null` meaning
six different things, and priced the acceptance as **no result surface may offer
retry on `notAnalysed` until A4 lands**. This is A4's half of that bargain.

### Decided

- **An absence is not a diagnosis.** `classify` returning `Future<InferenceResult?>`
  reports every failure through the same value, so the interface cannot tell a
  model that was never shipped from a run that timed out. The first means the
  feature is unavailable and there is nothing to retry; the second means a run
  failed and retrying is exactly right. One value cannot carry both, and no
  amount of care at the call site recovers information the return type discarded.

- **Twelve causes, grouped by the reader's remedy.** The grouping is the
  justification for the number: a taxonomy that does not change what anyone does
  is decoration.

  | Nothing to do — the build is wrong | Retrying is the right response | Re-export the model |
  | --- | --- | --- |
  | `contractMissing` | `timeout` | `contractUnsupported` |
  | `contractMalformed` | `interpreterError` | `modelContractMismatch` |
  | `modelMissing` | `isolateFailure` | `outputInvalid` |
  | `modelEmpty` | `imageMissing` | |
  | | `imageUndecodable` | |

  **Six are the ones ADR 0011 enumerated** (`0011:95-97`) — a missing model
  asset, an isolate spawn failure, a timeout, a decode failure, a class-count
  mismatch and an inference error — which are `modelMissing`, `isolateFailure`,
  `timeout`, `imageUndecodable`, `modelContractMismatch` and `interpreterError`
  here. `modelContractMismatch` widens the class-count case to cover the input
  tensor too, since the contract now declares both and the loaded interpreter
  can disagree with either.

  **Three are new**, and arrive with the `spec.json` contract this ADR's spec
  introduces: a contract can be absent, unreadable, or written to a schema the
  reader does not implement.

  **Three are facts the code already distinguishes and then discards on the way
  out.** `initialize` separates an empty asset from an absent one via
  `_modelUnavailable` (`inference_service.dart:124-128`); `_runInference`
  separates a missing image file from an undecodable one (`:211` against
  `:215`); and `buildDistribution` refuses a non-probability tensor for a
  different reason than a class-count mismatch (`:347-351` against `:333-334`).
  Separating them costs nothing and recovers information that already existed.

- **An enum outcome with a nullable payload, not a sealed hierarchy.** SPEC 0030
  established this shape for `ImageQualityVerdict` / `ImageQualityReport`, and
  the precedence order in `code_conventions.md` puts an established project
  pattern above a framework default. Two report types with two different shapes
  in one service layer is what ignoring that costs.

- **`rejectedOod` is declared and has no producer.** It is the reserved
  not-soil signal. Whether it comes from a trained negative class or from the
  quality gate plus a threshold is open and informed by experiment E12.
  Declaring the member now keeps that decision from being foreclosed by an enum
  someone has to widen later, and widening a type the UI switches over is the
  expensive kind of change.

- **No fallback is ever silent.** A missing or unreadable contract produces its
  own cause and stops the classification. It does not fall back to the values
  the contract replaced. This is the same reasoning
  [`ADR 0012`](0012-released-model-artifact-tracked-in-git.md) used to reject
  an untracked contract file: replacing hardcoded copies with a file nobody can
  verify relocates the problem instead of fixing it, and a fallback makes the
  application look functional against a model it cannot describe.

## Considered Options

- **Keep `null` and add a separate `lastFailureCause` getter on the service.**
  Rejected. It is the smallest diff and it is wrong: the cause and the result
  would be two reads of a mutable object with a classification in flight
  between them, so a second capture starting before the first is rendered
  reports the wrong cause. A defect that only appears under concurrency is worse
  than the one being fixed.

- **Throw a typed exception per failure.** Rejected. Failure here is an
  expected outcome, not an exceptional one — no model artifact ships with the
  repository today, so the common path is a failure — and the project's
  established shape for an expected negative outcome is a verdict, per SPEC
  0030. It would also put a `try`/`catch` around a call that already runs inside
  an isolate boundary with its own error handling.

- **Three or four causes instead of twelve**, collapsing everything the user
  cannot act on into one `unavailable`. Rejected, but it is the closest call
  here. It reads better and it loses the diagnostics: work item A5 counts
  failure causes apart to decide what to fix, and a counter that says
  "unavailable" tells nobody whether the artifact is missing from the build or
  the interpreter is failing on a device. The grouping in the table gives the
  interface its three-way choice without the counters losing the detail.

- **Defer the taxonomy to its own later record.** Rejected. The `spec.json`
  contract cannot be read without deciding what happens when it cannot be read,
  and ADR 0011's retry prohibition would otherwise stand after A4 had nominally
  landed.

## Consequences

- `classify` changes its return type. `capture_screen.dart` is the only
  production caller, and its four-member `ClassificationStatus` UI state machine
  keeps its name and meaning — the cause travels alongside it rather than
  replacing it. The domain type is called `ClassificationOutcome` for that
  reason: `capture_ui_state.dart:10` already owns the other name, and the two
  are not variants of one idea. One tracks where a screen is in an operation,
  the other reports what an operation concluded.

- **The isolate boundary carries the report, not the result.** Five of the
  twelve causes are produced inside `_runInference`, which answers on a
  `SendPort`. A taxonomy produced behind a boundary that only transports
  `InferenceResult?` is not implementable, so the message type changes with the
  return type — a consequence worth naming because it is invisible from the
  public signature.

- **ADR 0011's prohibition lifts, but not automatically.** Retry becomes
  offerable on the causes in the middle column. Deciding which of them the
  interface actually offers retry for, and what copy each one carries, is the
  UI/UX terminal's roadmap item 2. This record makes the distinction available;
  it does not make it visible.

- **A5 gains something to count.** ADR 0013's local-first counters are keyed by
  model version; failure causes are the second dimension worth counting apart,
  and they exist only after this.

- The label list, input size and normalization stop being Dart constants, so
  `contractMissing` becomes the ordinary state of a fresh checkout — as it
  already is in substance, since no `.tflite` ships either. What changes is that
  the application now says which of the two is missing instead of reporting
  neither.

- Every new cause is a public enum member. Adding one later is a widening that
  every exhaustive `switch` must handle, which is the pressure that keeps the
  taxonomy honest: a cause is added when something can genuinely fail that way,
  not when a message would read better.
