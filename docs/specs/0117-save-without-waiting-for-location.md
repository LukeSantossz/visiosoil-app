# SPEC: feat(capture): let a capture be saved without waiting for location

## Problem

On the capture screen, "Salvar registro" stays disabled while the location is being resolved, and the location fetch may take up to its 20-second timeout. A user whose classification has already settled still has to wait, often in the field with a weak GPS fix, for a value the record does not require. A record already saves without coordinates when location is denied or times out (SPEC 0099).

The UI/UX roadmap's item 7, "Named processing phases, Save ungated from location", sets the criterion `save_not_gated_by_location`: "with classification settled and location pending, Save is enabled and the record persists with null coordinates". SPEC 0116 delivered the phases and left this half.

## Design Decision

**Save waits for the classification and for a save already in flight, not for the location.** `CaptureScreen` passes `CaptureActions` a busy flag of `isClassifying || isSaving`, dropping `isLocating`. The classification still gates Save, because a record saved mid-classification would lose its class.

**A save made while locating keeps what the screen holds at that moment.** `_saveRecord` already reads `_state.latitude`, `_state.longitude` and `_state.address`. While locating, those are null, so the record gets null coordinates and the unavailable-address text, as a record saved after a denied location does. The location chip keeps saying "Localizando..." until then, so the user can see that location is still pending.

**A reading that arrives after the save is dropped.** A successful save pops the screen, and `_fetchCurrentLocation` already returns when the widget is unmounted. A failed save keeps the screen, and a reading that arrives then fills the state as usual, so a retried save can include it.

## Alternatives Considered

- **Relabel the button "Salvar sem localização" while locating.** Rejected for now: the location chip already shows "Localizando..." next to the photograph, and a label that changes under the user's finger mid-tap would be its own surprise.
- **Save at once, then add the coordinates to the record when they arrive.** Rejected: it needs an update path after the screen has closed, and it would write the record twice. It is closer to the address backfill #327 left out of scope.
- **Keep the gate, and shorten the location timeout.** Rejected: it still blocks the user, and a shorter timeout would lose fixes that a patient user would have got.

## Scope

- Includes:
  - `lib/core/features/capture/capture_screen.dart`: the busy flag passed to `CaptureActions`.
  - Tests in `test/features/capture/capture_screen_test.dart`.
- Does NOT include:
  - `CaptureActions`, whose `isBusy` contract is unchanged.
  - The location timeout, `LocationService`, and the chip copy.
  - Backfilling coordinates into a saved record.

## Acceptance Criteria

- `save_not_gated_by_location`: with the classification settled and the location still pending, "Salvar registro" is enabled, and tapping it creates one record with null latitude and longitude and the unavailable-address text.
- `save_still_waits_for_the_classification`: with the classification running and the location resolved, "Salvar registro" is disabled.
- `a_save_tapped_right_after_a_retry_waits_for_it`: when a retry and a save are tapped in the same frame, before the screen rebuilds, no record is created. `_saveRecord` checks the running classification itself, because the button's callback comes from the last build. Found by R3 on #333.
- `a_late_reading_after_a_failed_save_is_kept`: when a save made while locating fails, a reading that arrives afterwards appears in the location chip.
- The existing capture-screen tests pass unchanged.

## Reproducibility

`flutter test test/features/capture/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- A user who taps Save one second before the fix arrives loses the coordinates for that record. The chip shows that location is still pending, and the record states it has no location, as one saved with location denied does.
- On the API 34 emulator, saving while location was still resolving froze the app (#332's evidence). The main thread was blocked in the geolocator plugin's `LocationManager.removeNmeaListener`. It was the emulator's GNSS service and was not seen on a phone. This change makes saving while locating more likely, so a phone check before the Play release (#290) should include it.
