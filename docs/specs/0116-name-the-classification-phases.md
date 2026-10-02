# SPEC: feat(capture): name the classification phases instead of a single spinner

## Problem

While a photograph is classified, the capture preview shows one chip, "Classificando...", with a spinner (#326). The analysis takes a few seconds and runs real, distinct steps inside the inference isolate: decode, find the A4 sheet and the soil on it, describe the texture, score. None of them reaches the screen, because the isolate answers only with the final `ClassificationReport`.

The UI/UX roadmap's item 7 sets two criteria for this: `phases_are_named` ("a named phase is shown and changes when the phase does") and `phase_changes_announced` ("transitions ... are announced to assistive technology").

## Design Decision

**Four phases, each posted by the isolate as it starts.** A new `ClassificationPhase` enum in `classification_report.dart` names them, in the order `runInference` runs them:

| Phase | Starts before | Chip |
| --- | --- | --- |
| `readingPhotograph` | reading and decoding the file | "Lendo a foto..." |
| `findingSheet` | orienting the frame and running the measurer, which finds the A4 sheet and the soil on it | "Procurando a folha A4..." |
| `describingTexture` | cutting the patch grid and describing each patch | "Descrevendo a textura..." |
| `scoring` | scoring the patches with the contract | "Calculando a classe..." |

Cutting the grid and describing the patches share one phase because the cut is fast and has no name a user would recognise.

**The isolate posts each phase on the port it already answers on.** `runInference` takes an optional `onPhase` callback. The entry point passes one that sends the phase over `responsePort`. `classify` now reads the port as a stream:
- a `ClassificationPhase` is handed to `classify`'s new optional `onPhase` callback;
- a `ClassificationReport`, or the `null` exit notice, ends the call as it does today.

The single timeout still covers the whole call, from the first message to the report. The result contract, the causes and the teardown do not change. A caller that passes no `onPhase` sees exactly today's behaviour.

**The capture state carries the current phase.** `CaptureUiState` gains `classificationPhase`, cleared when a capture starts, set from `onPhase` only for the current generation, so a superseded capture cannot move the chip. While classifying, the chip shows the phase's label, or "Classificando..." before the first phase arrives.

**Phase changes are announced.** The classification chip is wrapped in `Semantics(liveRegion: true)`, so TalkBack and VoiceOver read each new label.

**A refusal is not given a phase label.** The issue asks that a refusal leave the last reached phase identifiable. The cause chip from SPEC 0105 already does that: each refusal cause names the step that refused, such as "Folha A4 não encontrada" for the sheet. A second label would repeat it.

## Alternatives Considered

- **A percentage bar.** Rejected: the steps have no honest fraction. The reference app in PR #323 fakes one on a timer, which is what #326 rules out.
- **A separate `ReceivePort` for phases.** Rejected: a second port needs its own teardown, and one port keeps the messages in the order they were sent.
- **Five or six phases (decode, orient, measure, cut, describe, score).** Rejected: orienting and cutting take milliseconds, and a label that flashes past is noise to a sighted user and an interruption to a screen-reader user.
- **Showing the last phase next to a refusal's cause chip.** Rejected as redundant with the cause chip, as above.

## Scope

- Includes:
  - `lib/core/services/classification_report.dart`: `ClassificationPhase`.
  - `lib/core/services/inference_service.dart`: `runInference`'s `onPhase`, the entry point's phase messages, and `classify`'s `onPhase` and stream read.
  - `lib/core/features/capture/capture_ui_state.dart`: `classificationPhase`.
  - `lib/core/features/capture/capture_screen.dart`: passes `onPhase` and stores the phase for the current generation.
  - `lib/core/features/capture/widgets/capture_image_preview.dart`: the phase label and the live region.
  - Tests in `test/services/`, `test/features/capture/`, and the two test fakes of `classify` that must accept the new parameter.
- Does NOT include:
  - Cancelling a classification (`processing_is_cancellable`), the quality gate, and the Save gating of roadmap item 7.
  - Any change to the causes, the timeout, or what a record saves.
  - A phase label after a refusal.

## Acceptance Criteria

- `run_inference_posts_the_phases_in_order`: `runInference` on a photograph that classifies calls `onPhase` with the four phases, in table order, each once.
- `a_refusal_stops_the_phases_where_it_happened`: on a photograph without a sheet, `onPhase` receives `readingPhotograph` and `findingSheet` only.
- `classify_relays_the_isolate_phases`: with an injected entry point that sends two phases and then a report, `classify` calls `onPhase` with both, in order, and returns the report.
- `classify_without_on_phase_is_unchanged`: the same entry point, called without `onPhase`, returns the same report.
- `phases_are_named`: on the capture screen, a classification that reports `findingSheet` shows "Procurando a folha A4...", and the label changes to "Descrevendo a textura..." when that phase arrives.
- `phase_changes_announced`: the classification chip sits in a live region.
- `a_superseded_capture_cannot_move_the_phase`: a phase from a discarded capture does not change the chip of the current one.
- The existing `classify` timeout and teardown tests pass unchanged.

## Reproducibility

`flutter test test/services/ test/features/capture/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumes an enum value can be sent between isolates. It can: `SendPort.send` copies enum values within one isolate group, and `Isolate.spawn` keeps the worker in the caller's group.
- On a fast device a phase may last a frame or two, so a sighted user may not see every label. The labels only promise the step in progress, not a duration.
- `inference_service.dart` is the ML session's ground. No open pull request touches it today, so this spec is the only change in flight there.
