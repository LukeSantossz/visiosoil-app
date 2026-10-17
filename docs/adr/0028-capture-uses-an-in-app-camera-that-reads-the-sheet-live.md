# ADR 0028: Capture uses an in-app camera that reads the sheet live

## Status

Accepted 2026-10-17, promoted from
[SPEC 0165](../specs/0165-capture-through-an-in-app-camera-with-a-sheet-guide.md)
at the Spec Gate, with
[SPEC 0166](../specs/0166-read-the-sheet-live-on-the-camera-preview.md) and
[SPEC 0167](../specs/0167-capture-automatically-when-the-sheet-reads-green.md),
the three slices of the guided capture.

## Decision

**The app owns its camera.** Capture runs through an in-app screen built on the
`camera` plugin, which draws the A4 sheet's outline, the soil target and a
level over its own preview. `image_picker` stays only as the fallback for a
device whose camera the plugin cannot open.

**The live guidance is the sheet reader itself.** The preview is read on the
device by the same `findSheet`, `locateSoilDisc` and `patchGeometry` that judge
the still, with the released contract's numbers. No other detector and no new
threshold decide what the user is told about the sheet or the soil. The still
is still judged in full by the reader, so the live verdict guides and never
classifies.

**The photograph is taken automatically** once that guidance has been green and
steady for one second, and the manual shutter is never disabled.

## Why

**The refusals that stopped every real photograph are framing errors.** On
2026-10-05, 31 photographs were taken to the protocol of ADR 0017. The reader
refused 5 for a sheet cropped or not found, and stopped the other 26 before the
grid: 24 for a soil patch of about 5 cm where the protocol asks for 8 to 10, and
2 for a photograph too coarse ([the check](../ml/sheet-reader-real-photographs.md)).
Every one of these can be seen while the photograph is framed, and none could
be shown: the system camera gives the app no preview and no surface to draw on
(`docs/design/ux-2026/06-capture-experience.md` §1). The first Play release
waits for a photograph that classifies (ADR 0026), so this is on its critical
path.

**Reusing the reader keeps one judge.** A separate live detector would tell the
user one thing and the reader another, and every threshold in it would be new
and uncalibrated. That is the failure ADR 0009 and the capture dossier warn
against: a live signal invented for the purpose.

## Considered Options

- **Keep the system camera and teach the protocol before it.** SPEC 0142 did,
  and the session that followed still produced 5 cm patches. Rejected: nothing
  can be shown while the photograph is framed.
- **A platform document scanner** (`google_mlkit_document_scanner`, VisionKit's
  document camera). Rejected: both return a cropped, enhanced page, and the
  reader needs the whole frame untouched; the ML Kit scanner is Android-only.
- **A lighter live detector**, such as an edge or rectangle detector, beside the
  reader. Rejected for the reason in the second paragraph of Why.
- **Manual capture only**, the dossier's default until live signals are
  calibrated. Rejected by the Developer: the tap shakes the phone at the moment
  of the shot. The dossier's caution is kept by the field session SPEC 0167
  requires before the trigger is considered settled.

## Consequences

- **Two dependencies arrive:** `camera` and `sensors_plus`. iOS declares
  `NSMotionUsageDescription` and `NSMicrophoneUsageDescription`, the latter
  because the plugin's setup asks for it although the app passes
  `enableAudio: false`; the Android release manifest must not gain
  `RECORD_AUDIO`, which the Play Data safety answers (#293) depend on.
- **The camera's lifecycle becomes the app's code**, because the plugin no
  longer manages it: release on leaving the foreground, re-create on return,
  and a permission revoked meanwhile.
- **`LostCaptureService` serves only the fallback.** A photograph taken in the
  app's own screen exists unsaved for a frame, so it needs no recovery.
- **The reader's inputs must stay grey.** The live path feeds it a grey frame;
  a colour-dependent step added to `findSheet` or `locateSoilDisc` would need
  the live conversion changed with it.
- **The field session decides the trigger.** If fewer than 9 of the first 10
  automatic photographs classify, a follow-up spec turns automatic capture off
  and the guidance stays.
