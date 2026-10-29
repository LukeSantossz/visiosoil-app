# SPEC: feat(corpus): give every texture a generic cell built from its own sources

## Problem

A classified sample often gets no management tip, and when it gets one, the tip rests on sources chosen for another soil.

- **One manifest feeds every cell.** `corpus/sources/substance.manifest.json` was curated for `Argilosa|tb_oxidic` (SPEC 0072), and `src.probe` reads it by default for all twelve substance cells. All twelve cells of the corpus `2026.10.28.1` therefore read the same three Cerrado PDFs about phosphorus, soil-analysis reading and gypsum.
- **Two classes have nothing.** None of the three documents is about a sandy or a very clayey soil. Arenosa grounds 0 of 3 cells and Muito Argilosa 0 of 3, so a record of either class always reads as abstained.
- **The clay-activity split is nominal.** The three families of one class read the same documents, so no difference between them comes from a source. Family-specific cells exist only because the key has three families, not because the sources say anything different about each.
- **A record without a family gets nothing.** `CorpusComposer.compose` looks up a substance cell only through a clay-activity family, which comes from the grid or the biome default. A record saved without GPS has neither, so it composes to `insufficient_evidence`.

The Developer's target, set on 2026-10-29, is that every classified sample gets tips for its texture, grounded in trusted web sources. The family refines a tip only where family-specific sources exist.

## Design Decision

**Each texture class gets a generic cell, `<class>|generic`, built from sources chosen for that class. A family-specific cell exists only where it has its own manifest. The app falls back to the generic cell whenever no family-specific cell answers.**

- **One manifest per cell.**
  - The sources for a cell live in `corpus/sources/<slug>.manifest.json`, where the slug is the cell key written the way `src.probe` writes it (`|` → `__`, space → `-`).
  - Each manifest's `cell` field must equal the key its file name gives.
  - The present manifest becomes `Argilosa__tb_oxidic.manifest.json`, because its sources are about oxidic Cerrado soils.
  - `src.probe --cell` reads the manifest of the cell it is given, unless `--manifest` names another.
- **Generic keys.**
  - `src.keys` adds `GENERIC = "generic"` and `generic_keys()`, one key per class of the shipped contract.
  - `describe_key` describes a generic key by the texture alone: "solo de textura arenosa, sem distinção da atividade da argila".
- **What a release holds.**
  - `release.py` requires a cell for every generic key, plus one for each family-specific key that has a manifest in `corpus/sources/`.
  - A missing cell, or a cell whose key has no manifest, fails the release by name.
  - The eight cells that abstained in `2026.10.28.1` because their sources were never about them leave the corpus. They are not rebuilt as abstentions.
- **Sources.**
  - The candidates come from my web research together with `src.search`. Each URL must:
    - be on the `src.search.ALLOWLIST` domains;
    - be fetched through `src.llm.http_transport` as a PDF with a text layer;
    - have its passage within `PASSAGE_CHAR_LIMIT`;
    - be recorded with `pages`, `tier`, `year` and a `why`.
  - A generic cell needs at least one source of tier 1 to 3, since tier 4 never carries a claim alone (research-agent §8.1).
  - **The candidate list is shown to the Developer, and the build runs only after they approve it.** Their approval is recorded in the pull request.
- **App lookup, in `CorpusComposer.compose`.**
  1. When a family is known (from the grid, or else the biome default) and its family-specific cell exists with at least one tip, that cell is used, as today.
  2. Otherwise the class's generic cell is used. This covers a record without GPS, a family without a cell, and a family-specific cell that abstained.
  3. `TipsCoverage` describes the cell that composed:
     - when the generic cell composed, `substanceIsGeneric` is true, `clayActivity` is null and `clayActivityAssumed` is false;
     - when a family-specific cell composed, the coverage is as today.
  - Status follows the cell used, by the existing rule: a generic cell that abstained makes the result abstained.
- **An interim re-release.**
  - The cells are rebuilt with the chain as it stands: `qwen2.5:7b` and generate prompt version 6, with the refusals of SPEC 0230 and SPEC 0231.
  - The output is released as a new corpus version, with `humanReview: false` and the advisory disclaimer, as in the Developer's decision of 2026-10-28.
  - Two judges, themed tips and the target of three tips per class belong to a later spec, which rebuilds the corpus again.

## Alternatives Considered

- **Keep twelve family cells and give each one its own sources.** Rejected for now. Few trusted documents speak to one texture under one clay family, so most cells would still abstain, and a family difference the sources do not state would be invented. The family stays only where a manifest exists.
- **Fall back to the generic cell only when the family is unknown.** Rejected. A family-specific cell that abstains leaves a classified sample with no tips, which is the gap this spec closes.
- **Compose the generic and the family-specific cell together.** Rejected. Their tips can repeat or contradict each other, and the composer has no rule for merging two substance layers. One cell answers.
- **Build the generic cells by hand-writing tips from the sources.** Rejected. It bypasses the grounding check, which is the only check on a tip.

## Scope

- Includes:
  - per-cell manifests under `corpus/sources/`, and the rename of the present one;
  - `src.keys` (`GENERIC`, `generic_keys`, `describe_key`), `src.probe` (manifest by cell) and `src.release` (the expected keys);
  - `CorpusComposer.compose` (generic fallback, coverage) and `Corpus.genericKey` in Dart;
  - tests in `corpus/tests/` and in `test/services/` (`corpus_composer_test.dart`, `corpus_research_service_test.dart`, `released_corpus_test.dart`);
  - the rebuilt `assets/corpus/corpus.json` (the grids are unchanged), and the corpus version, README and agent-instruction text that name the release.
- Does NOT include:
  - a second judge, themed tips, the three-tips-per-class target or a retry that is told why (a later spec);
  - the model study (a later spec);
  - fetching corpus releases over the network (a later spec);
  - the land-use and unit layers, `generate.md` or the refusals;
  - any UI change. `TipsCoverage` is not displayed today.

## Acceptance Criteria

- Python, in `corpus/tests/`:
  - `test_generic_keys_cover_every_class`: `generic_keys()` returns `<class>|generic` for each class of the contract, in its order.
  - `test_describe_key_names_the_texture_alone_for_a_generic_key`: the description of `Arenosa|generic` names "textura arenosa" and no family.
  - `test_probe_reads_the_manifest_of_its_cell`: without `--manifest`, the manifest path for `Muito Argilosa|generic` is `corpus/sources/Muito-Argilosa__generic.manifest.json`.
  - `test_manifest_cell_must_match_its_file`: a manifest whose `cell` differs from its file name's key is refused.
  - `test_release_requires_every_generic_cell`: a release missing one generic cell fails and names it.
  - `test_release_refuses_a_family_cell_without_a_manifest`: a family-specific cell with no manifest in the sources directory fails the release.
  - `test_release_requires_a_family_cell_that_has_a_manifest`: a family-specific manifest without its cell fails the release.
  - `test_every_manifest_is_on_the_allowlist`: every URL of every manifest in `corpus/sources/` is admitted by `src.search.ALLOWLIST`, and every generic manifest has a source of tier 1 to 3.
- Dart, in `test/services/`:
  - `a_record_without_a_family_composes_the_generic_cell`: with no clay activity and no biome, the result carries the generic cell's tips, and `substanceIsGeneric` is true.
  - `a_family_without_a_cell_composes_the_generic_cell`: with a family that has no cell, the generic cell composes, and `clayActivity` is null.
  - `an_abstained_family_cell_falls_back_to_the_generic_cell`: with a family cell that abstained, the generic cell composes.
  - `a_family_cell_with_tips_is_used`: with a grounded family cell, that cell composes, and coverage is as before.
  - `a_record_without_location_gets_tips`: `CorpusResearchService` with no `SiteKey` returns the generic cell's tips for the class.
  - `it_holds_every_generic_key` (replacing `it_holds_every_substance_key`): the released corpus has a generic cell for each class, and every other substance key is a `<class>|<family>` of a known class and family.
  - The present released-corpus tests that walk every substance key are rewritten to walk the keys the release holds.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1, Python 3.12.

- Tests:
  - `python -m pytest corpus/tests -q`
  - `flutter test`
  - `flutter analyze`
  - `mf check`
- Corpus build, with Ollama serving `qwen2.5:7b` on Vulkan (seed 1234, temperature 0):
  1. For each key the release expects, run `python -m src.probe --cell "<key>"`.
  2. Run `python -m src.release --cells <out> --grids <grids> --version <version>`.
- Each cell's run manifest records the passage each check quoted, and it stays on the machine that built it (SPEC 0161).

## Risks and Assumptions

- **A 7B model still grounds weakly.** The re-release carries the same risk as `2026.10.28.1`, which is why the disclaimer and `humanReview: false` stay. The hardening spec rebuilds the cells again.
- **A generic cell can still abstain.** If no tip of a class survives grounding, that class reads as abstained. This is accepted for the interim release and is the target of the hardening spec.
- **Trusted documents may be scarce for one class.** If no allowlisted PDF passes the fetch checks for a class, that is reported to the Developer before the build, and a release is not made with that class's manifest empty.
- **Cached results compose again.** The new corpus version makes every cached tip stale through `CachedManagementTips.isStaleAgainst`, so the cache is rebuilt on its next read. Nothing in the database changes.
- **Coverage changes meaning slightly.** `clayActivity` was the family the lookup tried; it becomes the family of the cell that composed. Nothing reads it today.
