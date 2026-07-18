# SPEC: fix(inference): release interpreter in finally so a failed run cannot skip close()

## Problem

In `_runInference`, `interpreter.close()` sits on the success path only, so any throw between `Interpreter.fromBuffer` and that line leaves the native interpreter handle unreleased.

## Scope

- Includes: wrapping the interpreter's create-to-use section in `lib/core/services/inference_service.dart` (lines 178-207) in `try { ... } finally { interpreter.close(); }`; removing the now-redundant explicit `close()` at line 187 so the handle is never closed twice; a test proving the interpreter is closed when the inference run throws.
- Does NOT include: the isolate lifecycle or the timeout path (issue #73, spec `0009`); the label/preprocessing single-source-of-truth work (#116/#79); any change to `initialize()` or its retry logic; any change to the argmax or `resolveTextureLabel` behavior.

## Acceptance Criteria

- `interpreter_is_closed_when_the_inference_run_throws` — a run that throws inside `interpreter.run` still reaches `close()` exactly once.
- `interpreter_is_closed_when_output_tensor_inspection_throws` — a throw from `getOutputTensor(0).shape` still reaches `close()`.
- `interpreter_is_closed_when_the_label_is_rejected` — the early `return null` for an incompatible class count (line 202) still closes the interpreter.
- `interpreter_is_closed_exactly_once_on_the_success_path` — no double close after the explicit `close()` is removed.
- `classify_still_returns_null_on_a_failed_run` — existing behavior is unchanged; the `catch` at line 208 still swallows into `null` and logs.
