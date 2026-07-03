# SPEC: fix(share): fall back to text-only share when the record photo is corrupt or zero-width

## Problem

When a record's photo file is present but corrupt, truncated, or empty, `ShareService.shareRecord`
hands its bytes to `ShareContentBuilder.composeCard`, whose `instantiateImageCodec` throws, so
sharing fails with a generic error snackbar instead of degrading to the text-only caption the
service already produces for the missing-file case.

## Design Decision

Wrap only the `composeCard` call in `ShareService.shareRecord` in a `try`; on a decode/compose
failure, `developer.log` it and fall back to `SharePlus.instance.share(ShareParams(text: caption))`
then return, mirroring the existing missing-file path. The wrap is narrow (around `composeCard`
alone) so a genuine platform `share()` failure still propagates and the temp-dir write/cleanup
semantics are unchanged. The corrupt/empty case is thus handled inside `ShareService`, before it
ever reaches the last-resort `catch (_)` in `details._shareRecord`.

## Alternatives Considered

- **Positive-dimension guard in `composeCard` (`photo.width > 0`)** — rejected: `instantiateImageCodec`
  throws on undecodable/empty/truncated bytes before any dimension is read, and Flutter codecs never
  yield a zero dimension without throwing, so the guard defends an unreachable state.
- **Broaden `catch (_)` in `details._shareRecord` to retry text-only** — rejected: pushes share-domain
  fallback into the UI layer, duplicates the caption path, and leaves `ShareService` still throwing
  for a case it owns.
- **Up-front probe decode to validate the photo** — rejected: doubles the decode work and still needs
  the same try/catch, cost for no behavioral gain.

## Scope

- Includes:
  - A narrow `try` around `composeCard` in `ShareService.shareRecord`; on failure, log the cause and
    share `ShareParams(text: caption)` then return.
  - Tests in `test/services/share_service_test.dart` for a present-but-corrupt (truncated) photo and an
    empty (zero-byte) photo: both share caption-only, create no temp artifacts, leak no directory.
- Does NOT include:
  - Any positive-dimension guard in `share_content_builder.dart` (unreachable given the codec throws first).
  - Any change to `details._shareRecord` — its `catch (_)` stays as the last-resort net for genuinely
    unexpected faults (e.g. a platform `share()` throw).
  - Any change to `caption`/`composeCard` output for valid photos, or to the missing-file path.

## Acceptance Criteria

- `shares_caption_only_when_photo_is_present_but_corrupt` — a record whose file holds truncated/undecodable
  bytes shares with `files` null/empty and `text` non-null; no temp directory remains.
- `shares_caption_only_when_photo_is_empty` — a zero-byte photo file behaves identically.
- `deletes_temp_dir_and_rethrows_when_platform_share_throws` (existing) still passes — the new fallback
  wraps only `composeCard`, so a real platform `share()` throw is not swallowed.
- `flutter_analyze_clean_and_full_suite_green`.

## Reproducibility

- `flutter analyze`; `flutter test test/services/share_service_test.dart` (+ full suite). Flutter 3.x /
  Dart 3.10.4+, `share_plus` with the `share_plus_platform_interface` dev-dependency fake seam
  (`SharePlatform.instance`) already used by the existing tests. No randomness.

## Risks and Assumptions

- Assumption: `ui.instantiateImageCodec` throws (not returns) on empty/truncated bytes, so one `try`
  around `composeCard` covers both empty and corrupt; if a future codec returned a zero-dimension image
  instead, `scale` would go non-finite and this spec would need the excluded dimension guard.
- Assumption: silent degrade-to-caption is the desired UX for a corrupt photo (consistent with the
  missing-file path); a visible "photo unavailable" notice would be a separate UI change.
- No ADR — a localized graceful-degradation fix, not a hard-to-reverse decision.
