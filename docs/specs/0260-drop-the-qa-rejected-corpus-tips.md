# SPEC: fix(corpus): drop the QA-rejected corpus tips

## Problem

Human QA on [PR #473](https://github.com/LukeSantossz/visiosoil-app/pull/473) rejected two management tips that remain in the bundled corpus `2026.10.31.1` ([Trello card](https://trello.com/c/xbqjHg92)). Both tips deny a property that follows from the texture class name, the same failure mode SPEC 0230's build gate now refuses at generation time. Shipping them contradicts the review and misleads agronomists reading Dicas de manejo.

- **`Arenosa|generic`:** tip text containing `A textura arenosa do solo não implica em baixa retenção de água`.
- **`Argilosa|generic`:** tip text containing `A textura argilosa não significa que o solo é mais propenso a formação de agregados`.

After removal, `Arenosa|generic` must keep two tips, `Argilosa|generic` one tip, and `Argilosa|tb_oxidic` unchanged (one tip). Every generic texture cell must stay `grounded` with at least one tip.

## Design Decision

**Edit the released artifact in place**, following the precedent of `5d9e5c2` (drop a false sandy tip without rerunning the Python build). Bump `corpusVersion` to `2026.10.31.2` so cached tips stale correctly (SPEC 0069). Do not rewrite surviving tips, sources, limitations, or grids.

## Alternatives Considered

- **Rebuild the cells with the pipeline.** Rejected for this change: QA already named the bad tips; a hand drop is bounded, fast, and matches the prior false-tip drop.
- **Rewrite the tips.** Out of scope; QA rejected the claims, not the wording alone.

## Scope

- Includes:
  - `assets/corpus/corpus.json`: delete exactly the two tip objects above; bump `corpusVersion` from `2026.10.31.1` to `2026.10.31.2`;
  - `test/services/released_corpus_test.dart`: regression tests that the substrings never appear in any tip text and that `Arenosa|generic` and `Argilosa|generic` stay grounded with at least one tip;
  - the living documents that name the bundled corpus version, so none names a release the app no longer holds: `README.md` (Current Features and Current Limitations), `docs/agents/project.md` with the instruction files `mf agents sync` generates from it, and the status note of `docs/plans/research-agent-implementation-map.md`.
- Does NOT include:
  - rerunning `corpus/` build or changing `.bin` grids;
  - editing other tips, sources, or limitations;
  - dated records that name `2026.10.31.1` as the release of their time (`docs/studies/`, `docs/specs/`, the example command in `corpus/README.md`);
  - UI, camera, TalkBack, or sync behaviour.

## Acceptance Criteria

- `qa_rejected_tip_claims_are_absent`: no released tip text contains either QA-rejected substring.
- `generic_cells_still_grounded_after_drop`: `Arenosa|generic` and `Argilosa|generic` each have `status` grounded and `tips.length >= 1`.
- `the_released_corpus_parses` and the existing composition tests in `released_corpus_test.dart` still pass on `corpusVersion` `2026.10.31.2`.
- `flutter test test/services/released_corpus_test.dart` passes.
- No file in the Scope's living documents names `2026.10.31.1`, and `mf check agents` passes.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/services/released_corpus_test.dart`, then `flutter analyze` and `mf check` when the CLI is available.

## Risks and Assumptions

- **Hand-edited release.** The dropped tips are no longer described by a build manifest on device; acceptable for two QA-named removals, same as the earlier false sandy tip drop.
- **Stale cache.** Devices with cached tips for `2026.10.31.1` refresh on next compose after upgrade; expected.
- **Assumption:** no other cell repeats either substring (verified by the regression test scanning all tip texts).
