# SPEC: fix(capture): strip EXIF metadata from captured photos

## Problem

Captured photo originals stored under `soil_images/` retain EXIF (including GPS)
— an uncontrolled duplicate of the location VisioSoil already records explicitly
— and on Android (the primary platform) `image_picker`'s `requestFullMetadata:
false` does not remove it, so the leak persists at rest and would exfiltrate once
`RemoteSyncBackend.uploadBlob` uploads raw image bytes.

## Design Decision

Strip metadata at the single durable-storage boundary,
`DefaultImageStorageService.saveCapturedImage`. For a JPEG source, read its EXIF
with `decodeJpgExif`, rebuild an EXIF block that keeps only the orientation tag,
and rewrite it with the `image` package's `injectJpgExif`, which swaps the EXIF
APP1 segment while preserving the entropy-coded scan data. This drops GPS and all
other metadata but keeps orientation, because both `Image.file` (display) and
`img.decodeImage` (the classifier's decode) apply the EXIF orientation — so
keeping the tag holds the stored file lossless, its decoded pixels byte-identical
to the source (no inference-distribution change and same on-screen orientation),
while it stays a small JPEG. Any non-JPEG source is raw-copied unchanged:
capture is camera-only (JPEG on both platforms; iOS converts HEIC to JPG), and
the `image` package cannot read or write non-JPEG metadata (its PNG encoder omits
EXIF and its PNG `eXIf` decode is disabled), so a non-JPEG re-encode would add
cost and pixel risk for no verifiable privacy gain. Keep `requestFullMetadata:
false` at the capture site as cheap defense-in-depth (it reduces metadata on
iOS). No new dependency: `image ^4.3.0` (resolved 4.8.0) is already a production
dependency.

## Alternatives Considered

1. Flag only (`requestFullMetadata: false`) — REJECTED: `image_picker_android`
   0.8.13+15 contains no reference to the flag, so it is ignored for camera
   captures and GPS survives on the primary platform; it does not solve the
   Problem. Kept only as iOS-side defense-in-depth.
2. Decode → re-encode as JPEG dropping EXIF — REJECTED: re-compressing the DCT
   data shifts pixel values, changing the distribution the on-device model sees
   versus training (train/serve skew); the audit flagged this inference risk.
3. Decode → re-encode as PNG (for every capture, or as a non-JPEG fallback) —
   REJECTED: pixel-lossless but inflates stored-file size several-fold for
   photographic content, and the `image` package cannot round-trip non-JPEG
   metadata anyway (PNG encode omits EXIF; PNG `eXIf` decode is a disabled TODO),
   so a fallback re-encode would strip nothing verifiable while risking pixels.
4. Strip at upload time in `RemoteSyncBackend.uploadBlob` — REJECTED: leaves
   EXIF-bearing originals at rest until sync ships (#55–57 are open); the goal is
   no leak at rest.

## Scope

- Includes:
  - `DefaultImageStorageService.saveCapturedImage` strips EXIF from JPEG sources
    with `injectJpgExif` and an empty `ExifData`; non-JPEG sources are raw-copied
    unchanged (preserving the existing contract).
  - Keep `requestFullMetadata: false` at
    `lib/core/features/capture/capture_screen.dart` (already committed).
- Does NOT include:
  - Re-encoding non-JPEG sources (raw-copied; see Design Decision).
  - Re-processing images already stored before this change.
  - Changing `InferenceService` decode/resize behavior.
  - Any `RemoteSyncBackend` / upload-side change.
  - Changing how coordinates are captured or stored (`LocationService` remains
    the sole source of location).
  - Stripping XMP metadata (a separate, rare APP1 signature) or bumping /
    adding image dependencies.

## Acceptance Criteria

- `stored_jpeg_has_no_gps_exif`: saving a source JPEG that carries GPS EXIF
  yields a stored file whose decoded EXIF has no GPS tags.
- `stored_jpeg_pixels_identical_to_source`: the decoded pixels of the stored
  JPEG equal the decoded pixels of the source (no inference drift).
- `stored_jpeg_preserves_exif_orientation`: a source JPEG with an EXIF
  orientation tag yields a stored file whose EXIF orientation tag is unchanged
  (display parity preserved).
- `non_jpeg_source_is_raw_copied_unchanged`: a non-JPEG (or non-image) source is
  stored byte-for-byte, preserving the existing copy contract.
- `save_still_throws_filesystemexception_on_unreadable_source`: an unreadable or
  missing source still throws `FileSystemException` (existing contract).
- `refusing_to_overwrite_existing_stored_image_preserved`: the existing
  exclusive-write guard against clobbering another record's image still holds.
- `existing_storage_and_capture_tests_stay_green`.

## Reproducibility

`flutter test test/services/image_storage_service_test.dart` then `flutter
test`; `flutter analyze`. Deterministic, no randomness. Toolchain Flutter 3.44.1
/ Dart 3.12.1; `image` 4.8.0.

## Risks and Assumptions

- Assumption: capture is camera-only and `image_picker` returns JPEG on both
  platforms (iOS converts HEIC to JPG), so the JPEG strip covers every real
  capture. Invalidated only if a non-JPEG camera source is introduced (e.g. a
  gallery source, explicitly out of scope), in which case that file would be
  raw-copied and any embedded metadata retained.
- Orientation: the EXIF orientation tag is deliberately preserved. Both
  `Image.file` (display) and `img.decodeImage` (the classifier's decode) apply
  the EXIF orientation, so stripping it would rotate camera photos on screen and
  change the pixels the model receives (Android often tags orientation instead of
  rotating pixels). Keeping the tag holds both paths identical to today —
  verified by the pixel-identity test, which fails when orientation is stripped
  and passes when it is preserved.
- Residual: `injectJpgExif` strips the EXIF APP1 segment, not XMP; camera GPS
  lives in EXIF, so the documented threat is covered, but an XMP-embedded
  location (rare) would remain. Out of scope for this change.
