# SPEC: feat(corpus): keep rejected tips out of every release

## Problem

A tip that QA or the Developer rejects is removed only by editing the released `assets/corpus/corpus.json` by hand. Nothing in the corpus build records the rejection, so the next rebuild can release the same claim again, and with `humanReview: false` nobody reads it before it ships. It has happened four times:

- `O solo arenoso não necessariamente significa baixo teor de argila.` (`Arenosa|generic`), rejected by QA on PR #457 and removed by hand in `5d9e5c2`;
- `A textura arenosa do solo não implica em baixa retenção de água` (`Arenosa|generic`), rejected by QA on PR #473 and removed by hand by SPEC 0260;
- `A textura argilosa não significa que o solo é mais propenso a formação de agregados` (`Argilosa|generic`), rejected by QA on PR #473 and removed by hand by SPEC 0260;
- `O solo argiloso não significa que o potássio não-trocável é predominantemente indisponível para as plantas.` (`Argilosa|generic`), rejected by the Developer on 2026-11-05 and removed by hand by SPEC 0261.

A rule that refuses the shape of these tips is not an option. Generate prompt version 7 (`corpus/prompts/generate.md`) asks for at least one `nao_significa` tip per cell, and every one of the eight tips in corpus `2026.10.31.3` is a negation ("não significa", "não implica", "não necessariamente"). Refusing the shape would empty the corpus. What QA rejects is a particular claim, so a particular claim is what the build has to remember.

Source: Trello card "[P1] Corpus: QA-rejected tips come back on every rebuild" (Dev audit, 2026-11-04).

## Design Decision

**A versioned rejection list that the release applies.**

- `corpus/rejected_tips.json` holds one entry per rejected claim: `phrase`, the words that identify it; `foundIn`, the cell it was released in; `reason`; and `reference`, the review or spec that rejected it. The four claims above are its first entries.
- A tip matches an entry when its text, lowercased and with every run of whitespace collapsed to one space, contains the entry's phrase normalized the same way. The match applies to every cell, not only `foundIn`, because a claim false in one cell is false in any other, and a rebuild can move a claim between cells.
- `corpus/src/release.py` reads the list and drops every matching tip before it writes. Dropping a tip does not reindex sources, because citations point into the cell's own sources and the tips that remain keep theirs. A grounded cell left with no tips is released as the abstention `corpus/src/pipeline.py` writes: `status` `abstained`, the build's `ABSTENTION_DISCLAIMER`, its sources and limitations kept. This is the cell SPEC 0261 wrote by hand. The release prints each drop, naming the cell and the phrase.
- The release refuses, naming the cause, a list that is not a JSON array, or an entry with a missing or blank `phrase`, `reason` or `reference`. A blank phrase would match every tip.
- `test/services/released_corpus_test.dart` reads the same list and asserts that no released tip matches it, with the same normalization. The app's runtime is unchanged: the list lives in `corpus/` and is not an asset.

## Alternatives Considered

- **Refuse every negation at build time.** Rejected: it refuses all eight tips the corpus holds, because prompt version 7 asks for that shape.
- **Change the generate prompt to ask for fewer negations.** Rejected for this change: it changes what every cell says, and needs a rebuild and its own QA reading. The rejection list is needed either way, because a rebuild under any prompt can repeat a rejected claim.
- **A model-judged pass that asks whether a negation contradicts soil science.** Rejected for this change: a 7B judge can be wrong the way the 7B grounding check already is. It stays a possible later experiment.
- **Match exact tip text.** Rejected: a rebuild rarely repeats a sentence word for word. A phrase that names the claim catches its rewordings that keep those words.
- **Match only in `foundIn`.** Rejected, for the reason under Design Decision.

## Scope

- Includes:
  - `corpus/rejected_tips.json` with the four entries above;
  - `corpus/src/release.py`: read and check the list, drop matches, turn an emptied grounded cell into an abstention, print each drop;
  - `corpus/tests/test_release.py`: tests for all of the above, and that the shipped list holds the four known claims;
  - `test/services/released_corpus_test.dart`: `no_released_tip_is_on_the_rejection_list`;
  - `corpus/README.md` (Releasing the corpus) and `docs/agents/project.md` with the instruction files `mf agents sync` generates from it, to say that the release applies the list.
- Does NOT include:
  - rebuilding or re-releasing the corpus: `assets/corpus/` and `corpusVersion` stay as they are;
  - the generate or grade prompts, or any new build gate in `corpus/src/pipeline.py`;
  - a model-judged pass or a required `leitura_do_laudo` tip;
  - any app UI or Dart runtime code.

## Acceptance Criteria

- A release whose cells hold a tip matching an entry, in any cell and with any casing or spacing, writes `corpus.json` without it, and prints the cell and phrase (Python test, red before the change).
- A grounded cell whose every tip matches is released as the abstention: no tips, the abstention disclaimer, its sources and limitations kept, and it passes `validate_cell` (Python test).
- Tips that match nothing are released unchanged, citations included (Python test).
- A list that is not an array, or an entry with a blank `phrase`, `reason` or `reference`, is refused by name and nothing is written (Python test).
- The shipped `corpus/rejected_tips.json` holds the four claims with their references (Python test).
- `no_released_tip_is_on_the_rejection_list` passes on `assets/corpus/corpus.json` (Dart test).
- `every_class_and_family_composes` and the rest of `released_corpus_test.dart` still pass.
- `python -m pytest corpus/tests -q`, `flutter test`, `flutter analyze` and `mf check` pass, apart from the palette goldens that fail only on this machine.

## Reproducibility

Python 3.12 in `corpus/`: `python -m pytest tests -q`. Flutter 3.44.1, Dart 3.12.1: `flutter test test/services/released_corpus_test.dart`, then `flutter analyze` and `mf check`.

## Risks and Assumptions

- **A reworded claim can pass.** A rebuild that says the same thing in other words is not caught. The list makes a repeat less likely, not impossible, and the corpus still ships with `humanReview: false` and the advisory disclaimer.
- **A phrase that is too short drops good tips.** Each phrase is the distinctive part of the claim, and a reviewer adding one reads what it would match.
- **Normalization parity.** Python's `str.lower` and Dart's `toLowerCase` agree on the Portuguese letters these tips use. The Dart test runs on the released file, so a disagreement would show as a failing test, not a silent pass.
- **Dart test cannot be red first.** The released corpus already holds none of the four claims, so the Dart guard passes on its first run. The Python release tests carry the red-before-green step.
