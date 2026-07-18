# SPEC: fix(inference): kill the inference isolate on timeout instead of leaking it

## Problem

`Isolate.run(...).timeout(...)` abandons the awaited future but cannot stop the worker, so a timed-out classification keeps a native TFLite interpreter and a ~600KB float32 tensor alive until the isolate finishes on its own.

## Design Decision

Replace `Isolate.run` with a managed `Isolate.spawn` that owns a `ReceivePort`, so the timeout path has a handle to call `isolate.kill(priority: Isolate.immediate)` on. Collapse the two independent timeouts (15s inside `InferenceService`, 20s inside `CaptureScreen`) into the single one that can now actually cancel work — the service's — and have the caller simply await it. Add an `_isClassifying` re-entry guard to `_retryClassification`, mirroring the existing `_isCapturing`/`_isSaving` guards, so rapid retry taps cannot stack concurrent inference runs.

The port and the isolate are torn down in a `finally` so success, timeout and error all release them; this is the same discipline spec `0007` applies one level down to the interpreter.

## Alternatives Considered

- **Keep `Isolate.run` and only remove the caller's outer timeout.** Rejected: it removes the redundant source of truth but leaves the actual leak — `Isolate.run` still exposes no handle, so nothing can be killed.
- **Keep `Isolate.run` and have `_runInference` poll a cancellation flag through a `SendPort`.** Rejected: the expensive segments (`Interpreter.run`, `img.copyResize`) are single blocking native calls; a cooperative flag can only be checked between them, so the worst case — a hung inference run — stays uncancellable.
- **Reuse one long-lived inference isolate across calls instead of spawning per classification.** Rejected: it would amortize spawn cost, but killing it on timeout to reclaim the interpreter destroys exactly the state that reuse exists to keep, and it introduces cross-request state into a path that currently has none. Worth revisiting only if spawn cost shows up in profiling with a real model.
- **Move the timeout to the caller and leave the service untimed.** Rejected: the service owns the isolate handle, so it is the only layer that can honor a timeout with a kill. A caller-side timeout can only abandon.

## Scope

- Includes: `classify` and `_runInference` isolate lifecycle in `lib/core/services/inference_service.dart` (lines 130-153, constant `_inferenceTimeout` at line 67); removal of the redundant `_classificationTimeout` wrap in `lib/core/features/capture/capture_screen.dart` (lines 195-197, constant at line 56); an `_isClassifying` re-entry guard on `_retryClassification` (lines 234-238).
- Does NOT include: the interpreter `try/finally` (spec `0007`, landing first on the same file); the timeout duration value itself, which stays 15s; the existing `_requestGeneration` cancellation-token logic in `CaptureScreen`, which stays as the mechanism for discarding stale results; retry/back-off inside `initialize()`; any UI copy change on the retry chip.

## Acceptance Criteria

- `classify_returns_null_when_the_isolate_exceeds_the_timeout` — behavior at the boundary is unchanged for the caller.
- `isolate_is_killed_when_the_timeout_fires` — the spawned isolate is terminated rather than left running.
- `receive_port_is_closed_on_the_timeout_path` — no port leak.
- `receive_port_is_closed_on_the_success_path` — same teardown on success.
- `receive_port_is_closed_when_the_isolate_throws` — same teardown on error.
- `classify_still_returns_a_result_on_the_success_path` — existing passing behavior preserved.
- `retry_classification_is_ignored_while_a_classification_is_in_flight` — a second tap during an active run does not start a second isolate.
- `retry_classification_is_allowed_again_after_the_run_settles` — the guard clears on success, timeout and error alike.
- `capture_screen_no_longer_applies_a_second_timeout` — only one timeout governs a classification.

## Reproducibility

`flutter test test/services/inference_service_test.dart test/features/capture/capture_screen_test.dart`. Timeout tests use an injected short duration or a fake clock rather than a real 15s wait; no randomness. Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: `_inferenceTimeout` is reachable for injection in tests, or can be made so without widening the public surface. If it cannot be injected cleanly, the timeout tests use a stub inference function rather than a real 15s wait — a real-time wait in the suite is not acceptable.
- Assumption: no production caller other than `CaptureScreen` depends on the 20s outer timeout. To be verified by grep before implementation.
- Risk: `Isolate.spawn` requires a top-level or static entry point and a `SendPort` argument, which is a more verbose shape than `Isolate.run`. This is accepted as the cost of having a killable handle.
- Killing an isolate mid-`Interpreter.run` relies on the TFLite native allocation being owned by that isolate's heap. If a leak persists after the kill, the interpreter must be closed cooperatively before the kill, which would reopen the rejected cancellation-flag alternative.
