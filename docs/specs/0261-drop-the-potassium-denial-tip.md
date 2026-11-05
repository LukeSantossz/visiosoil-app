# SPEC: fix(corpus): drop the potassium denial tip

## Problem

After SPEC 0260, the only tip left in the `Argilosa|generic` cell of the bundled corpus `2026.10.31.2` is:

> O solo argiloso não significa que o potássio não-trocável é predominantemente indisponível para as plantas.

It has the shape QA rejected in the two tips SPEC 0260 removed: it denies a claim nobody made instead of advising a practice. It is also misleading on its own terms, because non-exchangeable potassium is, by definition, the fraction plants cannot take up readily. An agronomist reading Dicas de manejo for a clayey record gets nothing to act on and a statement that reads as wrong.

SPEC 0230's build gate does not refuse it, because it refuses only a tip that says its texture class does not mean a clay content. QA did not name this tip, so SPEC 0260 left it in place and the Developer asked for this change on 2026-11-05.

The cell answers only a clayey record that does not resolve a family: one without a biome or clay activity, or one whose family has no cell of its own, such as `pantanal`, whose default family is `intermediate`. A record in the five biomes whose default family is `tb_oxidic` composes from `Argilosa|tb_oxidic` and is unaffected.

## Design Decision

**Turn `Argilosa|generic` into the abstention the build itself writes**, editing the released artifact in place as SPEC 0260 did. The cell becomes what `corpus/src/pipeline.py`'s `_abstention` produces:

- `status` `abstained`;
- `tips` empty;
- `disclaimer` set to the build's `ABSTENTION_DISCLAIMER`, "Nenhuma fonte elegível sustentou uma orientação para esta combinação. Consulte a assistência técnica local.";
- `sources` and `limitations` unchanged, because they are what was consulted and the details screen lists them as consulted sources for an abstention.

`corpusVersion` goes from `2026.10.31.2` to `2026.10.31.3`, so cached tips go stale (SPEC 0069). The cell stays valid under `corpus/src/cell.py`'s `validate_cell`, which requires an abstained cell to carry no tips.

## Alternatives Considered

- **Keep the tip.** Rejected: it ships a statement that reads as wrong to the reader it is for.
- **Remove the tip and keep the cell `grounded`.** Rejected: a grounded cell with no tips is a state the build never writes, and the composer would report `insufficient_evidence`, which means the key matched no cell, when the cell exists and found sources.
- **Delete the cell.** Rejected: it breaks the rule that every class has a generic cell (SPEC 0234, `it_holds_every_generic_key`), and a clayey record without a family would read as no coverage instead of an abstention.
- **Rewrite the tip by hand.** Rejected: a tip written here is grounded by nobody, which the corpus exists to prevent.
- **Rebuild the cell with the pipeline.** Rejected for this change: a 7B rebuild can return the same denial shape, since no build gate refuses it, and it takes a local model run for one cell.

## Scope

- Includes:
  - `assets/corpus/corpus.json`: the `Argilosa|generic` cell as above, and `corpusVersion` `2026.10.31.3`;
  - `test/services/released_corpus_test.dart`: a regression test that no tip carries the potassium denial and that `Argilosa|generic` is an abstention with its sources kept; `generic_cells_still_grounded_after_drop` narrows to `Arenosa|generic`; the version pin moves to `2026.10.31.3`;
  - the living documents that name the bundled corpus version or say every cell is grounded: `README.md` (Current Features and Current Limitations), `docs/agents/project.md` with the instruction files `mf agents sync` generates from it, and the status note of `docs/plans/research-agent-implementation-map.md`.
- Does NOT include:
  - a build gate that refuses denial-shaped tips in `corpus/`, which is its own change;
  - rerunning the `corpus/` build or changing the `.bin` grids;
  - any other cell, tip, source or limitation;
  - dated records that name an earlier corpus version as the release of their time;
  - UI, which already renders an abstention.

## Acceptance Criteria

- `potassium_denial_tip_is_absent`: no released tip text contains `potássio não-trocável é predominantemente indisponível`.
- `argilosa_generic_abstains`: `Argilosa|generic` has `status` `abstained`, no tips, at least one source, and the abstention disclaimer.
- `every_class_and_family_composes` still passes: a clayey record without a family composes to `abstained`, never to `insufficient_evidence`.
- `qa_rejected_tip_claims_are_absent` passes with the version pin at `2026.10.31.3`.
- `flutter test` passes, apart from the palette goldens that fail only on this machine.
- No file in the Scope's living documents names `2026.10.31.2` or says every cell is grounded, and `mf check` passes.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/services/released_corpus_test.dart`, then `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Less coverage.** A clayey record without a family now reads an abstention with consulted sources instead of one tip. That is the intended trade: no tip rather than a misleading one.
- **Hand-edited release.** As in SPEC 0260, no build manifest describes the edit.
- **Assumption:** the abstention disclaimer is the build's current constant; the test pins it so a change to either side is seen.
