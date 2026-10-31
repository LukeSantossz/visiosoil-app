# SPEC: fix(tips): show the photo placeholder the history shows

## Problem

When the Dicas page has no photograph to show, its head shows a plain grey square.

- **Where.** `_RecordHeader` in `management_tips_section.dart` draws the record's photograph at 56 × 56 dp (PNG 20, SPEC 0205). Its placeholder is a `ColoredBox` in `surfaceContainerHigh`. That placeholder shows when the record has no image path, while the file loads, and when it fails to load.
- **What the rest of the app does.** The history and home tiles have a placeholder for the same three cases. They draw the class's texture colour at 30 % behind a landscape icon in that colour (`_Thumbnail` in `analysis_tile.dart`). The same record therefore looks one way in the list and another on its Dicas page.
- **The visual review names it.** The unslop review of 2026-10-31 found the grey box. Its direction keeps colour for the texture classes, and the tile placeholder already does that.
- **Decision.** The Developer approved this review item on 2026-10-31.

## Design Decision

**The Dicas head's placeholder is the history tile's: the texture colour at 30 % behind a landscape icon in that colour.**

- The colour is `SoilTextureColors.forClass(record.textureClass!)`. The head is only built for a classified record, since an unclassified one returns "Solo não classificado" first, so it has no neutral case.
- The icon is `Icons.landscape`, at 45 % of the 56 dp side, as in `_Thumbnail`.
- The 56 dp size, the medium radius and the loading and error paths stay as they are. Only what the placeholder draws changes.

## Alternatives Considered

- **Make `_Thumbnail` public and use it here.** Rejected: it also carries the tile's 8 dp radius, the Modo Sol edge and the fade-in, none of which PNG 20 draws on the Dicas head. Sharing it would change the head's look beyond this item.
- **Keep the grey box but add an icon.** Rejected: the tile placeholder already exists, and two placeholders for one record is the inconsistency the review names.

## Scope

- Includes:
  - `lib/core/features/details/management_tips_section.dart`, `_RecordHeader` only;
  - `test/features/details/management_tips_section_test.dart`.
- Does NOT include:
  - the history and home tiles;
  - the Dicas disclaimer banner, a separate review item.

## Acceptance Criteria

- `test/features/details/management_tips_section_test.dart`:
  - `tips_photo_placeholder_shows_the_class`: for an Argilosa record whose photograph is not loaded, `tips-record-photo` holds an `Icons.landscape` coloured `SoilTextureColors.forClass('Argilosa')`, over that colour at 30 %.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/details/management_tips_section_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **#465 (SPEC 0239) edits the same file.** Its hunks are in the section's state, above line 210. `_RecordHeader` is near line 830, so the two merge without a conflict.
- **A missing file in a test never loads.** The tests rely on the placeholder showing while the frame is null or the file fails, which is both of the paths it replaces.
