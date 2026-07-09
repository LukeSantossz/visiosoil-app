# SPEC: fix(capture): strip EXIF metadata from captured photos

## Problem

The camera capture site requests images with full metadata, so every stored
photo original retains EXIF (including GPS) — an uncontrolled duplicate of the
location the app already records explicitly — which would exfiltrate once
`RemoteSyncBackend.uploadBlob` starts uploading raw image bytes.

## Scope

- Includes:
  - Pass `requestFullMetadata: false` to `ImagePicker().pickImage` at the single
    default capture site (`lib/core/features/capture/capture_screen.dart:104`).
  - Record in this spec that photo originals stored from this change forward are
    EXIF-reduced; files already at rest are unaffected.
- Does NOT include:
  - Re-encoding, rewriting, or stripping metadata from images already stored in
    `soil_images/` (pre-existing files stay as they are).
  - Changing `ImageStorageService` copy behavior
    (`lib/core/services/image_storage_service.dart:73`).
  - Any upload-time or sync-side stripping in `RemoteSyncBackend`.
  - Changing how coordinates are captured or stored — `LocationService` remains
    the sole source of location data.
  - Any change to `InferenceService` or the ML pipeline.

## Acceptance Criteria

- `capture_requests_image_with_full_metadata_disabled`: exercising the widget's
  real default camera picker (permissions injected as granted, no `pickFromCamera`
  seam override) drives `ImagePicker().pickImage` such that a recording fake
  `ImagePickerPlatform.instance` observes `requestFullMetadata == false`.
- `existing_capture_widget_tests_stay_green`: the full existing capture test
  suite passes unchanged (save, location, and classification paths unaffected).
- `spec_records_exif_reduction_scope`: this spec states that stored originals are
  EXIF-reduced from this change forward and that pre-existing files are unaffected
  (satisfied by the Scope note above).
