# SPEC: feat(capture): open the new record's details after a save

## Problem

A confirmed save pops the capture screen, so the user lands back on whichever tab opened it and has to find the record again to see it in full.

The journey ends a save on details (`docs/design/ux-2026/02-user-journey.md` §2, `S --> T[Details]`; §3.9, "Transitions to — details"). The information architecture lists "after save" among details' entries (`docs/design/ux-2026/04-information-architecture.md` §5). SPEC 0125 opened details from history and left this entry out of its scope. This spec closes roadmap item 10.

On `main`, `_saveRecord` in `capture_screen.dart` discards the `SoilRecord` that `SoilRecordRepository.create` returns, then calls `context.pop()`.

## Design Decision

**A confirmed save replaces capture with the record's details.** `_saveRecord` keeps the record `create` returns and calls `context.pushReplacement('/details', extra: created.id)` where it called `context.pop()`. Back from details then returns to the tab that opened capture, as a pop does today.

Everything else in the save stays:
- the success snackbar "Registro salvo com sucesso!", which is shown on the scaffold messenger the app shares, so it stays visible over details;
- `AppHaptics.confirm()`;
- clearing the photograph and disposing of the picked file;
- the `mounted` check: a screen left during the save still navigates nowhere.

**A failed save does not move.** It keeps the photograph and its snackbar, as today.

**`/details` keeps its contract.** It still receives the record id through `state.extra` (SPEC 0125), and reads the record through `soilRecordByIdProvider`.

## Alternatives Considered

- **`context.go('/details')`.** Rejected: it would drop the main screen from the stack, so back would leave the app instead of returning to the tab.
- **`pop()` and then `push('/details')`.** Rejected: two navigations, with capture's exit animation played before details enters.
- **Show the record on the capture screen after the save.** Rejected: details already shows the record, its tips, share and delete. A second view of one record is what SPEC 0125 removed.

## Scope

- Includes:
  - `lib/core/features/capture/capture_screen.dart`: `_saveRecord`'s destination.
  - `test/features/capture/capture_screen_test.dart` and `test/features/capture/capture_permissions_test.dart`: their routed harnesses gain a `/details` stub that shows the id it receives.
- Does NOT include:
  - The result presentation on capture (roadmap item 2).
  - Details itself.
  - The lost-capture recovery (SPEC 0096), which opens capture through the same route and so inherits the new destination.

## Acceptance Criteria

- `save_opens_details`: a confirmed save replaces capture with `/details`, given the id `create` returned. Back from details returns to the screen that opened capture.
- `failed_save_stays`: a save whose `create` throws stays on capture, with the photograph and the error snackbar.
- The existing tests pass. Three of them assert that a save "pops back to `/`": `a successful save creates the record, shows success, and pops`, `a_failed_deletion_does_not_fail_the_save`, and the location-denied save in `capture_permissions_test.dart`. They are updated to expect the details stub, since that is the behaviour this spec changes.

## Reproducibility

`flutter test test/features/capture/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Details opens on a record just written, so `soilRecordByIdProvider` reads it after the write. `create` returns only after the insert completes, so the read finds it.
- A user who expected to return to the home after a save now sees details first, one back away. That is the journey's intended end.
