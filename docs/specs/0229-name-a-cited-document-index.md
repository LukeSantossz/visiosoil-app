# SPEC: fix(corpus): name a tip that cites a document by its index

## Problem

The build refuses a tip that states a number, and records it as `states a number: <text>` (SPEC 0160). A document index written into the tip's text is caught by that check too, and the record then names a cause the tip does not have.

- The B3 run of 2026-10-28 rejected this `Media|ta_less_weathered` tip twice, as `states a number`: "O solo de textura média não significa que o solo é arenoso. O documento [0] menciona que o solo de textura média tem argila de atividade alta, mas não indica que o solo é arenoso."
- The only digit in it is the `0` of "[0]". `_NUMBER` matches it, because a bracket is not a word character.
- The generate prompt says "Cite os documentos só pelos índices, nunca pelo nome". The model sometimes reads that as writing the index into the text, when the index belongs in the tip's `citations` field.

Refusing the tip is right. The app shows a tip's text to a reader who never sees the documents' order, so "o documento [0]" points at nothing. The citations field is what links the tip to its source. What is wrong is the recorded cause, which is the record the Developer reads to judge why a cell abstained.

## Design Decision

**A tip whose text holds a bracketed document index is refused as `cites a document by its index: <text>`, and the number check reads the text with the index removed.**

- `cites_a_document_index(text)` is true when the text holds a bracketed list of indices: one or more integers, comma-separated, such as "[0]" or "[0, 2]".
- In `build_cell`'s generate-and-check loop, each tip is checked before grounding is asked, in this order:
  1. a tip that cites a document by its index is refused as `cites a document by its index: <text>`;
  2. any other tip that states a number is refused as `states a number: <text>`, as today.
- `states_a_number` ignores a bracketed index, so a tip that holds only an index and no figure is not called numeric. The index is replaced by a space rather than removed, so a figure written against it ("Dose[0]18") is not glued to the word before and is still a number. This was added after review.
- When any tip in an attempt is refused for either cause, grounding is not asked for that attempt's tips, as SPEC 0160 already does for numbers.
- What abstains and what grounds does not change. A tip with an index was already refused. Only the recorded cause is new.

## Alternatives Considered

- **Strip the index and keep the tip.** Rejected. "O documento menciona…" still refers to a document the reader cannot identify. Removing the words around the index as well would be the build rewriting the model's claim, and grounding would then judge a sentence the model never wrote.
- **Change the prompt so the model keeps indices in `citations`.** Deferred. A prompt change is a new prompt version, and the release refuses cells from more than one build (SPEC 0227). The B3 run building today's cells is on version 6, so this change waits for the next build.
- **Leave the cause as `states a number`.** Rejected. The record is what tells the Developer why a cell abstained, and a wrong cause sends them after a number that is not there.

## Scope

- Includes:
  - `cites_a_document_index` and the new rejection in `corpus/src/pipeline.py`;
  - `states_a_number` ignoring a bracketed index;
  - their tests in `corpus/tests/test_pipeline.py`.
- Does NOT include:
  - the generate prompt, for the reason above;
  - the cells and manifests of the 2026-10-28 B3 run, which are built from the 0227 branch and stay as they were built. A manifest is not part of the release, so no shipped artifact carries the old cause;
  - the app, which never reads a rejection.

## Acceptance Criteria

- `test_a_tip_citing_a_document_index_is_rejected_by_that_cause`: for "O documento [0] menciona a argila." and "Segundo [0, 2], a argila importa.", the cell abstains after two attempts, and the rejections are `cites a document by its index: <text>`, twice. Grounding is not asked.
- `test_an_index_is_not_a_number`: `states_a_number` is false for "O documento [0] menciona a argila." and for "Segundo [0, 2], a argila importa.".
- `test_a_figure_beside_an_index_is_still_a_number`: `states_a_number` is true for "O documento [1] dá 18 mg dm-3." and for "Dose[0]18 mg dm-3.".
- Existing pipeline tests pass unchanged, the number cases of SPEC 0160 included.

## Reproducibility

Python 3.12. In `corpus/`, run `python -m pytest tests -q`. No model and no network.

## Risks and Assumptions

- **A bracketed integer list is taken to be a document index.** The tips are Portuguese prose for a reader. A bracketed integer that is not a citation, such as a footnote marker, would be meaningless to that reader as well, so refusing it costs nothing.
- **The B3 manifest of `Media|ta_less_weathered` keeps the old cause.** It stays local and is not shipped. The next build records the new one.
