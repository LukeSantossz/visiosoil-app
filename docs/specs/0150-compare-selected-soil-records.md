# SPEC: feat(history): compare selected Soil Records

## Problem

History selection mode offers one action, deletion (#361). An agronomist who
wants to compare two samples has to open each record in turn and remember the
first one's values while reading the second. Nothing in the app puts two
records side by side.

## Design Decision

**Selection mode gains a "Comparar selecionados" action.** It is an icon button
in the app bar, before "Excluir selecionados".

- It is enabled only when exactly two records are selected. With none, one, or
  three or more, it is shown disabled, so the action is discoverable and its
  rule is visible.
- Tapping it pushes `/compare` with the two ids, in selection order, as
  `state.extra`. Ids already travel this way to `/details` and `/preview`.
- History keeps its selection, so the back button returns to the same two
  records selected and another pair is one tap away.

**`/compare` is a new route showing `CompareScreen`.**

- The extra is a `List<int>` of two ids. Any other extra reads as two ids
  that do not exist (-1), as `/details` does, and so shows "not found".
- The screen loads each record through `soilRecordByIdProvider`.
- While either is loading, it shows the shared loading indicator.
- If either load fails, it shows the shared error state reading "Não foi
  possível carregar os registros." with a retry that re-reads both.
- If either record is missing or deleted, it shows the shared error state
  reading "Registro não encontrado", with nothing to retry.

**The comparison is read-only and aligned row by row.** The app bar reads
"Comparar registros" and has the platform back button, which returns to
history. Below it, one scrolling column holds:

1. The two photographs side by side, each square and cropped to fill.
2. The two identities side by side. Each is the record's labels
   (`labelsSummary`, SPEC 0149) when it has any, and "Sem identificação"
   otherwise.
3. One row per value. Each row has a caption across the full width, then the
   two records' values side by side:
   - "Classe textural": `displayTextureClass`, with the texture's colour dot.
   - "Confiança": `formattedConfidence`, which reads "-" for an unclassified
     record.
   - "Data da coleta": `formattedTimestamp`.
   - "Localização": the address, or "Endereço indisponível", with the
     coordinates on the next line when the record has them.

The two records are ordered by collection time, older on the left, whatever
order they were selected in. Before/after is the reading a comparison of
samples needs most often, and a fixed order means the same pair always
compares the same way.

**It stays readable on a phone.** Each side takes half the width, and text
wraps instead of being cut, so no value is hidden. A row grows to its taller
side. The screen lays out without overflow at 200 % text on a phone
(SPEC 0121) and passes Flutter's accessibility guidelines in both themes
(SPEC 0133).

**Nothing on the screen writes.** It has no edit, share, delete or capture
action, and a photograph is not a button.

## Alternatives Considered

- **Stack the two records vertically on narrow screens.** Rejected. Values
  could no longer be read across a row, and the second record's identity
  would scroll away from the first's. Half the width of a phone is enough for
  wrapped text.
- **Two independent columns, one per record.** Rejected. A wrapped address on
  one side would push every later value out of line with the other side.
- **Allow comparing more than two records.** Deferred. #361 asks for two, and
  three columns on a phone would no longer fit wrapped text.
- **Open details from a photograph or an identity.** Deferred. The issue asks
  for a read-only comparison with a direct return to history, and a second
  path into details adds a navigation question this change does not need.
- **Show the class distribution or the management tips.** Deferred. #361
  names photograph, texture result, confidence, collection time and location.

## Scope

- Includes:
  - `HistoryScreen`: the compare action and its enabled rule.
  - `app_router.dart`: the `/compare` route.
  - A new `lib/core/features/compare/compare_screen.dart` with
    `CompareScreen`.
  - The tests below.
  - `docs/agents/project.md` (with `CLAUDE.md` regenerated): nine routes, and
    the `compare` feature folder.
- Does NOT include:
  - Any repository, provider, model or schema change.
  - Any change to details, the grid or deletion.
  - Comparing more than two records, or any action on the compare screen
    other than going back.

## Acceptance Criteria

- `compare_needs_exactly_two`: in selection mode, "Comparar selecionados" is
  disabled with zero, one and three records selected, and enabled with two.
- `compare_opens_with_the_two_ids`: tapping it with two selected pushes
  `/compare` with those two ids, and history still shows both selected after
  returning.
- `compare_is_labelled`: the action has the tooltip "Comparar selecionados".
- `compare_route_is_registered`: `appRouter` registers `/compare`.
- `compare_shows_both_records`: for two classified records with labels, an
  address and coordinates, the screen shows both photographs, both
  identities, both texture classes, both confidences, both collection times,
  both addresses and both coordinate lines.
- `compare_orders_older_first`: the older record's identity is left of the
  newer one's, whichever id came first.
- `compare_shows_missing_values`: a record with no labels, no classification,
  no address and no coordinates shows "Sem identificação", "Não classificado",
  "-" and "Endereço indisponível", and no coordinates line.
- `compare_reports_a_missing_record`: if either id finds no record, the
  screen shows "Registro não encontrado".
- `compare_reports_a_load_error`: a failing load shows "Não foi possível
  carregar os registros.", and its retry reads both records again.
- `compare_is_read_only`: the screen shows no edit, share, delete or capture
  action, and tapping a photograph navigates nowhere.
- `compare_scales_to_200_percent`: long labels and addresses lay out without
  overflow at 200 % text on a phone.
- `compare_meets_guidelines`: the screen passes Flutter's four accessibility
  guidelines in every app theme.

## Reproducibility

```sh
flutter test test/features/compare test/features/history test/routes
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: half a phone's width fits each value.** A 360 dp phone gives
  each side about 160 dp. A long address wraps over several lines, which is
  what the 200 % criterion exercises.
- **Assumption: keeping the selection after returning helps more than it
  surprises.** It matches what a back button promises, and "Cancelar seleção"
  ends it in one tap.
- **Risk: a record deleted elsewhere while the screen is open.** The screen
  reads each record once, as details does, so it keeps showing what it read
  until it is opened again. Nothing on this device deletes from behind the
  screen today.
