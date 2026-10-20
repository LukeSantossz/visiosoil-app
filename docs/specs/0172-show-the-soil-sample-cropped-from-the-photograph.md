# SPEC: feat(capture): show the soil sample cropped and straightened from the photograph

## Problem

The capture preview and the record's details show the whole photograph, so the soil the agronomist prepared is a small patch amid the chair, the table and their feet, and nothing on screen shows what the classifier read.

## Design Decision

A top-level function measures the photograph as the classifier does — `findSheet`, then `locateSoilDisc` — and rectifies, with `rectifySheet`, a square on the sheet centred on the soil disc, reaching 15 mm past the disc on every side and kept inside the sheet. The square is reduced to at most 1024 px on a side and encoded as JPEG. It runs in a background isolate through a `FutureProvider.family` keyed by the photograph's path, so it is computed once per photograph and session, and both screens read the same provider. The capture preview and the details header show the sample in place of the photograph once it is ready. While it is being computed, and when the photograph has no readable sheet or soil, they show the photograph as today. The full photograph stays the stored one, and tapping the image still opens it whole in the full-screen preview. Nothing is persisted, so records saved before this change get their sample too.

## Alternatives Considered

- **Return the sample from the classification isolate and store it beside the photograph.** Rejected: it changes `ClassificationReport`, the capture save path and the repository's `create` signature, and leaves the records already saved without a sample. Measuring a second time costs about a second, once per photograph and session.
- **A crop rectangle on the original photograph, persisted in new columns.** Rejected: a tilted sheet gives a skewed, rotated crop, and it needs a schema change for a display concern.
- **Crop to the whole sheet.** Rejected by the Developer for option (a): the soil stays small on a sheet that is mostly white paper.

## Scope

- Includes:
  - `lib/core/services/descriptors/soil_sample.dart`: the function from a photograph's path to the sample's JPEG bytes, or null.
  - A provider in `lib/providers/` running it in an isolate per path.
  - `CaptureImagePreview` and the details header (`_HeroImageAppBar`) showing the sample when there is one.
  - Tests for each criterion.
- Does NOT include:
  - The history grid, the home's last analysis, the compare screen and the share card, which keep the photograph. A thumbnail grid would measure every record on open.
  - Any change to the classification, the stored photograph, the database or sync.
  - Caching the sample on disk.

## Acceptance Criteria

- `the_sample_is_centred_on_the_soil`: for a committed sheet photograph whose disc the reader measures, the sample is square, at most 1024 px on a side, and its centre region is darker than its border, which is paper.
- `the_sample_reaches_past_the_disc`: the sample's side spans the disc's diameter plus 30 mm, or less only where the sheet's edge bounds it.
- `no_sheet_no_sample`: a photograph refused as `sheetNotFound` or `sheetCropped`, or with no soil disc, gives null, and an unreadable file gives null.
- `the_preview_shows_the_sample`: the capture preview shows the sample's image once the provider resolves, and the photograph before it does or when it resolves to null.
- `the_details_show_the_sample`: the details header shows the sample when the provider resolves to bytes, and the photograph otherwise; tapping it opens the full photograph's preview as today.
- Device check (Developer): a saved record's details show the soil filling the header, straightened.

## Reproducibility

```sh
flutter test test/services/soil_sample_test.dart test/features/capture test/features/details
flutter analyze && flutter test && mf check
```

Flutter 3.44.1, Dart 3.12.1, `mf` v0.8.0.

## Risks and Assumptions

- Assumption: the reader's measurement is deterministic, so the sample shows the disc the classifier read.
- Risk: a second measurement of a 12 MP photograph takes about a second on a phone. It runs off the UI isolate, and the photograph is shown until it is ready.
- Risk: the provider keeps one sample (about 100 to 300 KB) in memory per photograph opened in a session.
- What would invalidate this spec: a sample that does not show the soil the classifier read, which would show the agronomist a different region from the one classified.
