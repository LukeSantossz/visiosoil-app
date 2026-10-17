# SPEC: docs: write the capture protocol

## Problem

No single document tells the person taking the photographs how to take one the app can classify, so the next session of real photographs risks repeating the faults of 2026-10-05, when none of 31 photographs classified (`docs/ml/sheet-reader-real-photographs.md`).

The protocol exists only in pieces: three sentences of product copy in `lib/core/constants/capture_protocol.dart`, the 2026-09-29 amendment of ADR 0017, the soil preparation ADR 0014 declares, and the limits the sheet reader and the patch grid enforce in code. The limits that refused that session are not written anywhere a photographer reads: the sheet's long side must span at least 2299 px, and the soil circle must be at least 63 mm across for nine patches to fit.

## Scope

- Includes:
  - `docs/capture-protocol.md`: a short, direct protocol in English, with what to prepare, how to frame and light the photograph, a checklist before the shot, and what each refusal the app names means and how to fix it. Every limit it states is the one the code enforces today, cited to its source.
  - `test/standards/capture_protocol_doc_test.dart`: holds the two numbers the document derives from the released contract to the contract, so a re-released geometry that moves them fails the suite instead of leaving the protocol stale.
- Does NOT include:
  - Any change to `lib/`, the in-app capture guide copy, `assets/models/spec.json`, the sheet reader or the patch grid.
  - Any claim of classification accuracy on real photographs: none has been classified yet.
  - A pt-BR version of the document. The in-app guide is the pt-BR surface, and documentation is in English.
  - Changes to ADR 0017, ADR 0014 or the withdrawn `docs/ml/collection-protocol.md`.

## Acceptance Criteria

- `the_protocol_states_the_least_sheet_span_the_contract_allows`: the document states the least number of pixels the sheet's 297 mm side must span, and it equals `ceil(297 / canonical_mm_per_px)` from `assets/models/spec.json`.
- `the_protocol_states_the_least_soil_circle_nine_patches_need`: the document states the least soil circle, in whole millimetres, and it equals the smallest disc `patchGeometry` accepts at the contract's `min_patches`, plus the reader's `soilMarginMm` on each side, rounded up.
- `the_protocol_names_every_refusal_a_retake_fixes`: for every cause whose capture-preview chip asks for another photograph rather than offering a retry, and that is not a contract cause, the document names the cause and quotes the chip's label, so a photographer can find the remedy from what the screen says.
- `mf check` passes.
