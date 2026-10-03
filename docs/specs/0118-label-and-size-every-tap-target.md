# SPEC: fix(a11y): label and size every tap target, and keep destructive actions apart

## Problem

The UI/UX audit's P0-4 found accessibility instrumentation "effectively absent", and P2-8 found destructive actions sitting next to confirmatory ones (`docs/design/ux-2026/03-problems.md`). The roadmap's item 3, "Accessibility baseline", was placed third on purpose, but no spec has taken it. On `main` today:

- **Five icon-only buttons have no label**, so a screen reader announces only "botão":
  - history's selection-mode close and delete;
  - the history search's clear button;
  - the preview's back and info buttons.
- **Three tappable surfaces are a bare `GestureDetector`.** They have no ink response, no button semantics and no label of their own:
  - the home's last-analysis row;
  - the history thumbnails;
  - the capture preview's retry chip.
- **Two destructive actions sit close to a confirmatory one:**
  - capture's "Descartar" is 8 dp under "Salvar registro";
  - details' "Excluir registro" is 16 dp under "Compartilhar".

## Design Decision

**This is the first slice of item 3: targets and labels.** Text scaling to 200 % and reduced motion are left to a later slice, because each needs its own screen-by-screen check.

**Every icon-only button gets a pt-BR tooltip.** Flutter uses the tooltip as the button's semantic label.

| Button | Tooltip |
| --- | --- |
| History, selection mode, close | "Cancelar seleção" |
| History, selection mode, delete | "Excluir selecionados" |
| History search, clear | "Limpar busca" |
| Preview, back | "Voltar" |
| Details, back | "Voltar", replacing `MaterialLocalizations.backButtonTooltip` |
| Preview, info | "Ver detalhes" |

Details' back button already has a tooltip, but it reads `MaterialLocalizations.backButtonTooltip`. The app registers no pt-BR localizations, so that tooltip is the English "Back". Adding `flutter_localizations` would change every Material string at once, so this slice uses the literal "Voltar" in both places.

**Every tappable surface is an `InkWell` on a `Material`.** That gives it ink, button semantics and keyboard focus.
- **The home row** is wrapped in `MergeSemantics`, so its thumbnail, class, place and date are read as one button.
- **A history thumbnail** gets `Semantics(label: "Registro de <data>", selected: …)`, so selection mode announces which records are selected.
- **The retry chip** keeps its text as the label.

The home row is already more than 48 dp tall. A history thumbnail is a grid cell, far larger than 48 dp. The chip's height is set by its text, so it gets `ConstrainedBox(minHeight: 48)` around the tappable area only, which leaves the visible chip unchanged.

**Destructive actions keep 24 dp from the confirmatory one.** Capture's gap between "Salvar registro" and "Descartar", and details' gap between "Compartilhar" and "Excluir registro", become `AppSpacing.xl` (24 dp). The roadmap sets 24 dp in `destructive_separated`.

## Alternatives Considered

- **One spec for all of item 3, text scale and reduced motion included.** Rejected: it would touch every screen at once. The 200 % check needs a reflow decision per `maxLines: 1` site, and the motion check needs every animation listed. Neither shares code with this slice.
- **A shared `VisioTappable` wrapper**, as the roadmap suggests. Rejected for now: three call sites with three different semantics (merged, selectable, chip) do not yet show one shape. A fourth site would.
- **`Semantics(label:)` on the icon buttons instead of tooltips.** Rejected: a tooltip also helps sighted users on long-press, and it is the idiom details' back button already uses.

## Scope

- Includes:
  - `lib/core/features/history/history_screen.dart` and `lib/core/features/history/widgets/history_filter_bar.dart`: the three tooltips.
  - `lib/core/features/history/widgets/history_grid.dart`: the thumbnail's ink and semantics.
  - `lib/core/features/preview/image_preview_screen.dart`: the two tooltips.
  - `lib/core/features/details/details_screen.dart`: the back tooltip.
  - `lib/core/features/home/widgets/last_analysis_section.dart`: the row's ink and merged semantics.
  - `lib/core/features/capture/widgets/capture_image_preview.dart`: the retry chip's ink, semantics and 48 dp target.
  - `lib/core/features/capture/widgets/capture_actions.dart` and `lib/core/features/details/details_screen.dart`: the 24 dp gaps.
  - Widget tests per surface, using Flutter's `labeledTapTargetGuideline` and `androidTapTargetGuideline`.
- Does NOT include:
  - Text scaling to 200 %, reduced motion, and labels derived from sample photographs (later slices of item 3).
  - The details and preview information architecture (item 10).
  - Any copy other than the tooltips.
  - Registering `flutter_localizations` for pt-BR.

## Acceptance Criteria

- `icon_buttons_are_labelled`: each tooltip in the table is found, on history in selection mode, the history search with a term, the preview and details. The preview also meets `labeledTapTargetGuideline`. No "Back" tooltip remains.
- `record_row_is_accessible`: the home's last-analysis row is a button with ink. It merges its class and date into one semantic node, and meets `androidTapTargetGuideline`.
- `history_thumbnails_are_accessible`: a history thumbnail is a button labelled "Registro de <data>" with ink. In selection mode it reports itself selected when selected.
- `retry_chip_is_accessible`: a retryable failure chip is a button labelled with its text, with a target at least 48 dp tall.
- `destructive_separated`: on capture with a photograph, and on details, the destructive button's top is at least 24 dp below the bottom of the button above it.
- The existing widget tests pass unchanged.

## Reproducibility

`flutter test test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Other Material defaults stay in English until `flutter_localizations` is registered, for example a date picker's labels and the default "Dismiss" of a modal barrier. This slice does not audit them.
- An `InkWell` paints its splash on the nearest `Material`, and a thumbnail's photograph would cover that `Material`. So the thumbnail's `InkWell` sits on a transparent `Material` laid over the photograph, inside the card's stack. The test checks where it sits; whether the ripple can be seen is left to a look on a device.
- The retry chip's larger target may overlap the location chip's area in the `Wrap` by a few dp. The chip row has spacing, so a tap still lands on one chip.
