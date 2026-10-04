# SPEC: feat(navigation): open details from history, and the photograph from details

## Problem

A history card opens the photo preview, which repeats the record's date and place and links on to details. So two screens show one record, and the less complete one is entered first.

The audit records it (`docs/design/ux-2026/03-problems.md` P2-3). The information architecture gives the target (`docs/design/ux-2026/04-information-architecture.md` §4): history opens details, and details' photograph opens a viewer that shows the photograph and nothing else. Roadmap item 10 closes it under four criteria (`docs/design/ux-2026/13-roadmap.md` §4): `tap_opens_details`, `hero_opens_viewer`, `viewer_is_photo_only` and `viewer_has_no_duplicate_info`.

On `main`:

```text
history ──tap──▶ /preview ──"Ver detalhes"──▶ /details
                 photo, date, place, a drag handle
```

- The preview's `_InfoPanel` repeats the date and the place, which details' info section already shows. Its `_DragHandle` suggests a sheet that never moves.
- Details' hero photograph is not tappable, so the full-screen viewer is reachable only through history.
- The home's last-analysis row already opens details.

## Design Decision

**History opens details.** A tap on a card outside selection mode pushes `/details` with the record's id, where it pushed `/preview`.

**Details' photograph opens the viewer.** The hero image in `_HeroImageAppBar` becomes a button labelled "Ampliar foto" that pushes `/preview` with the record's id. Its ink sits on a transparent `Material` over the photograph, as SPEC 0118 did for history's thumbnails.

**The viewer shows the photograph and one control.** `_PreviewContent` keeps the black canvas and the zoomable `InteractiveViewer` with its broken-image fallback, plus one button over the photograph: "Fechar", with `Icons.close`, which pops. These go:
- `_InfoPanel`, with its date, place and coordinates rows;
- `_DragHandle`;
- the "Ver detalhes" button, since details is now the screen underneath.

**The route keeps its contract.** `/preview` still receives the record id through `state.extra`, as `CLAUDE.md` describes for both record routes, and reads the record through `soilRecordByIdProvider`. While details is open, that provider already holds the record, so the viewer opens on it. Its loading and error views, unified by SPEC 0124, stay as the fallback for a record that disappears between the two screens.

## Alternatives Considered

- **Pass the image path to `/preview` instead of the id, and delete its loading and error views,** as the information architecture suggests. Rejected for now: it changes the route's contract and the router's typed `extra`, for states that are not seen while details holds the record. It can follow if the viewer is ever reached from elsewhere.
- **Open the viewer as a dialog over details instead of a route.** Rejected: system back and the router's history already behave for a pushed route, and the viewer is a full screen.
- **Keep a back arrow instead of a close button.** Rejected: the target names "a labelled close affordance", and the viewer has no title or hierarchy to go back through. System back still pops it.

## Scope

- Includes:
  - `lib/core/features/history/history_screen.dart`: the tap's destination.
  - `lib/core/features/details/details_screen.dart`: the hero as a labelled button.
  - `lib/core/features/preview/image_preview_screen.dart`: the viewer reduced to the photograph and "Fechar".
  - Tests in the history, details and preview test files.
- Does NOT include:
  - Opening details after a save (the information architecture's "after save" entry).
  - The preview's route contract, and its loading and error views.
  - History's card content (roadmap item 9).
  - Details' other sections.

## Acceptance Criteria

- `tap_opens_details`: outside selection mode, a tap on a history card pushes `/details` with that record's id.
- `hero_opens_viewer`: details' hero photograph is a button labelled "Ampliar foto". Tapping it pushes `/preview` with the record's id.
- `viewer_is_photo_only`: the viewer shows the photograph in an `InteractiveViewer`, and its only button is labelled "Fechar". Tapping it pops the viewer.
- `viewer_has_no_duplicate_info`: the viewer shows no "Capturado em", no "Localização", and neither the record's date nor its address.
- The existing tests pass, except two that pin what this change removes:
  - the preview's `icon_buttons_are_labelled`, which pins the two buttons this change replaces, is updated to the new single button;
  - SPEC 0027's `image_preview snaps its bottom-sheet radius to xl`, which requires the deleted sheet's radius, keeps only its check that no off-scale radius returns.

## Reproducibility

`flutter test test/features/history/ test/features/details/ test/features/preview/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- A user who learnt that a history card opens the photograph now lands on details first, one tap further from the full-screen photograph. Details shows the photograph at the top, and the tap on it is labelled.
- The hero's tap target is the whole expanded photograph, 280 dp tall. Scrolling the page starts on it too: a drag is not a tap, so `InkWell` does not fire on a scroll.
