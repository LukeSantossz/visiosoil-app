# Strip EXIF from captured photos at the storage boundary: lossless JPEG EXIF removal on copy, raw-copy for non-JPEG

The durable-storage copy owned by `ImageStorageService` (ADR 0002) stops passing
captured photo bytes through verbatim. `saveCapturedImage` now removes EXIF
(including GPS) from JPEG sources as it writes them into `soil_images/`, so stored
originals carry no uncontrolled location duplicate — the location the app keeps is
only the explicit one it records through `LocationService`. The removal is
lossless: it swaps the JPEG's EXIF APP1 segment for an empty one and leaves the
entropy-coded scan untouched, so decoded pixels are byte-identical to the source
and the on-device classifier sees no distribution shift. Non-JPEG sources are
raw-copied unchanged. `requestFullMetadata: false` is also set at the capture
site as iOS-side defense-in-depth.

## Status

Accepted. Implemented under issue #113 (SPEC `docs/specs/0002-strip-exif-from-captured-photos.md`
approved at the Spec Gate). Extends ADR 0002, which owns the storage/copy side of
the image-file lifecycle. Prompted by the 2026-07-03 security audit and confirmed
by the cross-provider (R2) review, which showed the capture-site flag alone does
not strip camera EXIF on Android.

### Decided
- **Strip at the storage boundary, not the capture site** — `image_picker`'s `requestFullMetadata: false` is ignored for camera captures on Android (verified: the flag has no reference in `image_picker_android` 0.8.13+15), so the removal must happen where every capture is durably written: `saveCapturedImage`.
- **Lossless EXIF removal for JPEG** — use `image`'s `injectJpgExif(bytes, ExifData())`, which replaces the EXIF APP1 segment while preserving the scan; stored pixels stay byte-identical to the source, avoiding train/serve skew for the future model.
- **Raw-copy non-JPEG sources** — capture is camera-only (JPEG on both platforms; iOS converts HEIC to JPG), and the `image` package cannot round-trip non-JPEG metadata (its PNG encoder omits EXIF; PNG `eXIf` decode is a disabled TODO), so re-encoding non-JPEG would strip nothing verifiable while risking pixels.
- **Keep the capture-site flag** — retained as cheap iOS-side defense-in-depth, not relied on for Android.

## Considered Options

### Where to remove the metadata
- **Capture-site flag only (`requestFullMetadata: false`)** — rejected: ignored by Android for camera captures, so GPS survives on the primary platform.
- **Upload time, in `RemoteSyncBackend.uploadBlob`** — rejected: leaves EXIF-bearing originals at rest until sync ships (#55–57 open); the goal is no leak at rest.
- **Storage boundary (chosen)** — the single durable-write chokepoint; removes the data before anything can read it back.

### How to strip a JPEG
- **Decode → re-encode JPEG dropping EXIF** — rejected: DCT requantization shifts pixel values, changing the distribution the model sees versus training.
- **Decode → re-encode PNG** — rejected: pixel-lossless but inflates stored size several-fold, and does not help non-JPEG (the library cannot carry non-JPEG EXIF anyway).
- **`injectJpgExif` with empty EXIF (chosen)** — segment-level swap, lossless, keeps the small JPEG, uses the existing `image` dependency, no hand-rolled JPEG parser.

## Consequences

- Stored soil photos no longer carry an EXIF GPS duplicate; when blob upload lands (#55/#56), raw image bytes will not exfiltrate a location the user did not choose to attach.
- The classifier is unaffected: `InferenceService` decodes stored files to pixels and does not apply EXIF orientation (`img.decodeImage` + `copyResize`, no `bakeOrientation`), and the strip preserves pixels exactly.
- Photos already stored before this change are not rewritten; the guarantee holds from this change forward.
- Residual: `injectJpgExif` strips the EXIF APP1 segment, not XMP; camera GPS lives in EXIF, so an XMP-embedded location (rare) would remain — out of scope.
- A non-JPEG source (only reachable if a gallery source is ever added, explicitly out of scope) would be raw-copied with any metadata retained.
