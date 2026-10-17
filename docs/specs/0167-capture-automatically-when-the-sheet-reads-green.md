# SPEC: feat(capture): capture automatically when the sheet reads green and the phone holds still

## Problem

Once the live reader says everything is right (SPEC 0166), the user must still reach for the shutter, and the tap itself shakes the phone at the moment the photograph is taken, in a field, often one-handed.

## Design Decision

**The guided camera takes the photograph itself when the guidance has been green and steady for one second.** `AutoCaptureTrigger` is a pure state machine. It holds no timer: it is fed two kinds of events, each stamped by an injected clock, and decides on each one.

- A **reading** event carries the banner's row after SPEC 0166's debounce and, when the sheet is found, the disc's diameter.
- A **tilt** event carries the smoothed tilt of SPEC 0165, at `SensorInterval.normalInterval`.

The **window** opens at the first event at which the banner is row 8, green, with a measured tilt. While it is open, every event must keep it qualified, or the window closes at once:

- the banner is still row 8;
- the largest smoothed tilt seen in the window minus the smallest is under 1.0°, so the phone is still;
- every reading's diameter differs from the previous reading's in the window by under 2.0 mm, so the reading is stable.

The trigger **fires** at the first event stamped at least 1000 ms after the window opened, provided the window holds at least two readings. With tilt events every 200 ms or so, that is within about 200 ms of the one-second mark.

**What the user sees.** While the window is open, a ring around the shutter fills in proportion to the time since it opened, and the banner reads "Segure firme…". A closed window empties the ring at once. When the trigger fires, a short white flash covers the preview, lasting `AppMotion.fast`, which is not shown when `MediaQuery.disableAnimationsOf` is true, as the app's other motion does. No haptic of its own is given: `CaptureScreen` already gives `AppHaptics.confirm()` when the photograph returns, which is the class of event `AppHaptics` assigns it. The trigger then follows the manual shutter's path of SPEC 0166: stop the reader and the stream, `takePicture`, pop `captured`.

**One photograph per visit, and the manual shutter wins.** One flag, `shooting`, is shared by the trigger and the shutter, and is set synchronously, before any `await`, by whichever acts first; the other then does nothing. A tap while the window is open sets it, closes the window and takes the photograph manually.

**A failed shot does not loop or lock.** If `takePicture` throws, whether the trigger or the shutter asked for it, the snackbar of SPEC 0165 shows, `shooting` is cleared, the stream and a new reader start, the ring is empty, and the trigger needs a new window: one that opens on an event stamped after the failure and lasts its full second. The shutter works at once.

**No proof of stillness, no automatic capture.** In `tiltUnavailable` (SPEC 0165), or after the live reader has fallen back (SPEC 0166), the trigger is disarmed: it opens no window and the ring is hidden. The manual shutter works as before.

**This is the departure `06-capture-experience.md` §4 asked to be argued.** That dossier makes automatic capture wait for "the live signals [to] have been calibrated in the field; an auto-shutter that fires on a bad frame is worse than no auto-shutter". The signal here is not a new heuristic: it is the reader that judges the still, fed the preview. The calibration the dossier asks for is still owed, and it is the field session below, which decides whether the trigger stays on.

**The field session closes the feature.** After this spec merges, the Developer takes a session on the surface of 2026-10-05, letting the trigger fire, until it has taken 10 photographs. Those 10, every photograph the trigger took and no other, are the session. It passes when at least 9 of them are classified, that is, `InferenceService.classify` reports a success for them; every other outcome, any named refusal or failure included, counts against it. On 2026-10-05, none of 31 was classified. The result is recorded in `docs/ml/sheet-reader-real-photographs.md`. If the session shows the tilt bands of SPEC 0165 or the bounds here wrong, a follow-up spec revises them, and the approved specs are not edited. If it fails, the trigger is turned off by a follow-up spec and the guidance stays.

## Alternatives Considered

- **Manual capture only, the dossier's default.** Rejected by the Developer: the tap shakes the phone at the worst moment, and every guided-capture product surveyed (identity verification, document capture) fires on its own once its checks pass.
- **An on-screen switch to turn the trigger off.** Deferred. Nothing yet says a user wants it, and the manual shutter is always there. The field session decides.
- **A numbered countdown.** Rejected. A ring that fills says the same without asking the user to read a number while holding still.
- **Taking several stills and keeping the sharpest.** Deferred. It needs a sharpness measure the app does not trust yet (#244).

## Scope

- Includes:
  - `lib/core/features/capture/guided_camera/auto_capture_trigger.dart`: the state machine.
  - `GuidedCameraScreen`: the ring, the banner's "Segure firme…", the flash, the shared `shooting` flag, and the re-arm after a failure.
  - Tests for each criterion.
  - After the field session: its result in `docs/ml/sheet-reader-real-photographs.md`.
- Does NOT include:
  - A switch to turn automatic capture off, a countdown, or multi-frame capture.
  - Any change to the reader, the guidance's conditions, or the classification of the still.
  - Live blur, exposure or glare checks.

## Acceptance Criteria

- `fires_after_one_steady_green_second`: green readings every 333 ms and tilt events every 200 ms, still and stable, fire the trigger on the first event stamped at or after 1000 ms from the window's opening, and on no event before it.
- `one_reading_is_not_enough`: a window that reaches 1000 ms holding a single reading does not fire, and fires at the next event once a second reading has arrived.
- `leaving_green_closes_the_window`: a non-green reading at 800 ms closes the window, and the trigger fires 1000 ms after the next window opens.
- `a_moving_phone_does_not_fire`: smoothed tilts spanning 1.0° within the window close it; tilts spanning 0.99° do not.
- `an_unstable_disc_does_not_fire`: consecutive diameters 2.0 mm apart close the window; 1.99 mm apart do not.
- `fires_once`: after firing, further green windows do not fire again.
- `the_shutter_wins`: a tap while the window is open takes one photograph, and the trigger does not fire afterwards; a tap and a firing in the same frame take one photograph.
- `a_failed_shot_rearms_after_a_new_second`: after a failed automatic shot, the trigger does not fire on events stamped before the failure, and fires after a new window of 1000 ms opened after it.
- `a_failed_manual_shot_unlocks`: after a failed manual shot, a second tap captures, and the trigger fires after a new window of 1000 ms opened after the failure.
- `no_tilt_no_trigger`: in `tiltUnavailable`, or after the reader's fallback, the trigger never fires and the ring is hidden.
- `the_ring_follows_the_window`: the ring shows half filled 500 ms into the window and empty after it closes.
- `the_automatic_shot_stops_the_stream_first`: on firing, the fake camera sees `stopImageStream` before `takePicture`, and `takePicture` once.
- `the_flash_respects_reduce_motion`: with reduce-motion on, firing shows no flash and still takes the photograph.
- `the_trigger_adds_no_haptic`: firing gives no haptic before the photograph returns; `CaptureScreen` gives its `confirm` once it does.
- Field session (Developer): of the first 10 photographs the trigger takes, at least 9 are classified, recorded as above with each one's outcome.

## Reproducibility

```sh
flutter test test/features/capture
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- **Risk: the trigger fires on a frame the still then refuses.** The preview and the still are not the same image. The cost is a retake, which the field session measures, and the still's refusal still names its cause.
- **Risk: a hand steady enough for the level is not steady enough for a sharp still.** The 1° stillness bound is a starting value, and the field session is where a blurred still would show.
- **Assumption: one second is short enough not to tire the user and long enough to prove stillness.** Revisited with the field session.
- **Risk: a session fails on the classifier, not on the capture.** The session counts classifications, so a photograph read correctly by the reader can still fail it if the classification fails for another reason. Each failure's named cause is recorded, which separates the two.
- **What would invalidate this spec:** a field session below 9 of 10, which turns the trigger off.
