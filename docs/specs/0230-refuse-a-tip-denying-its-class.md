# SPEC: fix(corpus): refuse a tip that denies the clay content its class states

## Problem

A texture class is a range of clay content. The groups the cells are keyed by are:

- arenosa: under 15% clay;
- média: between that and 35%;
- argilosa: 35% to 60%;
- muito argilosa: over 60%.

A tip that says its class does not mean a low or a high clay content denies what the class is, so it is false whatever the sources say.

The B3 run of 2026-10-28 grounded such a tip, and SPEC 0227 released it.

- `Arenosa|intermediate` carries one tip: "O solo arenoso não necessariamente significa baixo teor de argila."
- The grounding check judged it supported. The passage it quoted is real and is in the cited source, but it gives the critical phosphorus levels for four clay ranges. It says nothing about whether a sandy soil holds little clay.
- So the quote check (SPEC 0161) passed, because the passage is found, and the support judgement of the 7B model was wrong.
- The same confusion of texture class and clay content appears in two other cells of the run. The grounding check refused both, so they abstained.

The build cannot tell a supported claim from an unsupported one better than its model does. A tip that contradicts the class's own definition, though, can be told apart by its words, so the build checks it the way it checks a number (SPEC 0160).

## Design Decision

**A tip that says its texture class does not mean a clay content is refused before grounding as `denies the clay content its class states: <text>`. The one cell built with such a tip is rebuilt, and the corpus is released again as `2026.10.28.1`.**

- `denies_its_class_clay(text)` is true when all of these hold in one sentence:
  - the text names a texture class: "arenoso", "arenosa", "argiloso", "argilosa" or "textura média", with their plurals;
  - a negated verb of meaning follows: "não", up to two words, then "significa", "indica", "implica" or "quer dizer";
  - a clay content is its object, within three words: "teor de argila", "conteúdo de argila", "quantidade de argila", "percentual de argila", "porcentagem de argila" or "proporção de argila" (one word may sit before the "de"), or "pouca", "muita", "mais" or "menos argila".
- The phrase "muito argiloso" is covered, because it contains "argiloso".
- In `build_cell`'s generate-and-check loop, each tip is checked before grounding is asked:
  1. a tip that states a number is refused as `states a number: <text>`, as today;
  2. any other tip that denies its class's clay content is refused as `denies the clay content its class states: <text>`.
- When any tip in an attempt is refused for either cause, grounding is not asked for that attempt's tips, as SPEC 0160 does for numbers.
- **The rebuild:**
  - `Arenosa|intermediate` is rebuilt with `src.probe`, on the same model, seed and prompt versions as the other eleven cells. The release accepts the set, because it refuses only mixed models and prompt versions (SPEC 0227).
  - The other eleven cells are released as they were built. None of the four other grounded tips denies its class's clay content, and the check can only refuse, so an abstained cell rebuilt with it would abstain again.
  - The corpus version changes to `2026.10.28.1`, because the app's cache of tips compares versions by exact string (`CachedManagementTips.isStaleAgainst`), and a changed artifact under an old version would never replace a cached tip.

## Alternatives Considered

- **Edit or drop the tip by hand.** Rejected. The release ships one build's output (SPEC 0227). A tip removed by hand is a cell no build produced, and its manifest would no longer describe it.
- **Require the quoted passage to share the tip's words.** Rejected. This tip and its passage share "teor de argila", so the check would have passed it. A stricter overlap would refuse paraphrases the grounding check rightly accepts.
- **Ship the cell and correct it later.** Rejected. The Developer's decision to publish without human review is about tips nobody has reviewed. This one is known to be false.

## Scope

- Includes:
  - `denies_its_class_clay` and the new rejection in `corpus/src/pipeline.py`;
  - their tests in `corpus/tests/test_pipeline.py`;
  - the rebuilt `Arenosa|intermediate` cell and the re-released `assets/corpus/corpus.json`;
  - `docs/agents/project.md` and the generated instruction files, on the counts and the version.
- Does NOT include:
  - the generate prompt. A new prompt version would split the set into two builds, which the release refuses;
  - the grounding check itself;
  - the two grids, which do not change;
  - the retry, which repeats its first attempt under temperature 0 and a fixed seed. That is a separate decision.

## Acceptance Criteria

- `test_a_tip_denying_its_class_clay_is_rejected_by_that_cause`: these tips each make the cell abstain after two attempts, with `denies the clay content its class states: <text>` recorded twice, and grounding is never asked:
  - "O solo arenoso não necessariamente significa baixo teor de argila.";
  - "A textura argilosa não indica um alto teor de argila.";
  - "Solo muito argiloso não quer dizer que haja mais argila.".
- `test_a_tip_about_another_property_is_not_denying_its_class`: `denies_its_class_clay` is false for:
  - the four other tips the B3 run grounded;
  - "Solo argiloso não significa solo fértil.";
  - "A cor escura não indica o teor de argila.", which names no class.
- `test_a_number_is_named_before_a_denied_class`: "O solo arenoso não significa teor de argila abaixo de 15%." is refused as `states a number`.
- `released_corpus_test.dart` passes on the re-released `corpus.json`, and `Arenosa|intermediate` is not grounded on the tip above.
- Existing corpus and Flutter tests pass unchanged.

## Reproducibility

- Python 3.12. In `corpus/`, run `python -m pytest tests -q`. No model and no network.
- To rebuild the cell:
  1. `python -m src.probe --cell "Arenosa|intermediate" --model qwen2.5:7b --seed 1234 --out <dir>`
  2. Then `python -m src.release --cells <dir with the twelve cells> --grids <grids dir> --version 2026.10.28.1`.

## Risks and Assumptions

- **A narrow check catches one pattern.** It does not make the grounding check better. It refuses one claim that is false by definition, and the run shows the model making that claim more than once.
- **A tip with the words but a true claim is refused.** For example, a tip saying the class does not mean a *uniform* clay content. Refusing it costs one tip, and the cell abstains rather than ships a wrong one.
- **The rebuilt cell may abstain.** That is the expected outcome, because the retry repeats its first attempt. An abstained cell reads as absent coverage.
