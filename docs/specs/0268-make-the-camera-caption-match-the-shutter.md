# SPEC: fix(capture): make the camera's caption match its shutter

## Problem

The guided camera's caption says the shutter is released only when the three chips are ok, but the shutter takes the photograph while a chip still reads "Ajustando…".

## Design Decision

**The caption gives advice instead of describing a lock.** Under the shutter, "Captura liberada quando os 3 itens estiverem ok" becomes "Para a melhor foto, espere os 3 itens ficarem ok". The shutter's gate does not change.

The gate is deliberate:

- SPEC 0165 made the shutter always enabled, and records that the Developer rejected locking it until the level was green, because a lock that misjudges strands the agronomist in the field.
- SPEC 0166 says a reader that fails never blocks.
- SPEC 0191 kept the manual fallback for an unavailable reader, "to avoid trapping the user behind a failed checker", and draws an unknown reading as "Ajustando…" rather than as a success.

Today `_canCapture` holds the shutter only when a reading is known and fails: the sheet is read and not ready, or the light or the focus is read and not ok. While nothing has been read, the shutter takes the photograph. The caption is the only part of the screen that says otherwise. The UX audit of 2026-11-10 (finding UX-02) saw the shutter fire on the emulator with all three chips at "Ajustando…".

The new caption is true in every state:

- with a reading that fails, the shutter is held and a tap shows the warning (SPEC 0191);
- with every chip ok, the shutter fires;
- with a chip still adjusting, the shutter fires, and the caption has not claimed otherwise.

## Alternatives Considered

- **Hold the shutter until all three chips have a reading.** Rejected. It is the lock the Developer rejected in SPEC 0165. A reader that never answers, such as one on a slow phone or one that has failed, would leave the agronomist with no way to take the photograph.
- **Change the caption with the state, for example "Sem leitura ainda" while a chip adjusts.** Rejected for now. The chips already show "Ajustando…", so a second line saying the same thing adds text without adding information. One sentence that holds in every state is simpler.
- **Remove the caption.** Rejected. It is the one line that tells a first-time user what the three chips are for.

## Scope

- Includes:
  - the caption's text;
  - the guided camera tests that find the caption by its old words;
  - a row in `docs/design/v11/redesign.md` §0.2, because §3.4 there quotes the old caption.
- Does NOT include:
  - `_canCapture`, the chips, their thresholds or their copy;
  - the blocked-tap warning, haptics or shake;
  - the capture guide's text, the onboarding, or the guide-off camera (SPEC 0208), which shows no caption;
  - the shutter freeze seen on the emulator (UX-04), which is still unverified on a device.

## Acceptance Criteria

- `caption_does_not_promise_a_lock`: with the guide on and no reading yet, the chips read "Ajustando…", the caption reads "Para a melhor foto, espere os 3 itens ficarem ok", no text contains "Captura liberada", and a tap on the shutter takes one photograph.
- `guide_on_keeps_the_guide` finds the new caption, and `guide_off_hides_the_guide` finds no caption.
- `flutter analyze` reports nothing new, `flutter test` has no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/features/capture/guided_camera/`, then `flutter analyze`, `flutter test` and `mf check`. The tests use the fake camera and reader of `test/support/guided_camera_harness.dart`.

## Risks and Assumptions

- **A user may still shoot while a chip adjusts.** Accepted. This is the behaviour SPEC 0165 chose. The caption now asks the user to wait, without promising the screen will make them.
- **Assumption:** no other text on the camera or in the capture guide says the shutter is locked. A search of `lib/` for "liberada" on 2026-11-10 found only this caption. In the docs, it found the redesign's §3.4, which the §0.2 row covers, and SPEC 0208's test name, which stays as that spec's record.
