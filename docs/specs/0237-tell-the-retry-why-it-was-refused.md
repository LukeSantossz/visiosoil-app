# SPEC: fix(corpus): tell the retry why its tips were refused

## Problem

When the build refuses a batch's tips, it asks the model again with the same prompt, and the model gives the same answer.

- **The loop.** `_build_batch` generates a batch's tips, refuses any tip that states a number, cites a document by its index or denies its class's clay content, then asks grounding for the rest. A batch with any refused or unsupported tip is generated again, up to `max_attempts` (2) times.
- **The second attempt cannot differ.** The build runs at temperature 0 with a fixed seed (SPEC 0227). The second attempt sends the first attempt's prompt byte for byte, so it gets the first attempt's answer, and the same tip is refused again. SPEC 0230 recorded this and left the retry to a separate decision.
- **What it costs.** Every refused batch spends a second generate call for nothing. A cell whose batches are all refused abstains, and the B3 run abstained on eight of twelve substance cells.
- **The most frequent cause.** The prompt says "Cite os documentos só pelos índices, nunca pelo nome", and the model reads it as leave to write "[0]" or "documento 1" in the tip's text. SPEC 0229 refuses such a tip.
- **Decision.** The Developer asked on 2026-10-29 for a retry that carries the reason for the refusal, and for its rebuild to run once, chained with the crop, season and phase rebuild.

## Design Decision

**A batch's next attempt is told which tips the last attempt lost and why. The generate prompt also says where a citation belongs.**

- `LLMClient.generate_cell(question, documents, rejected=())`. [rejected] is a sequence of lines, one per tip the last attempt lost. Each line is the tip's text in quotes, then a colon and the reason:
  - `states a number` → "traz um número; escreva a direção que os números mostram, sem números";
  - `cites a document by its index` → "cita um documento no texto; cite só no campo citations, pelos índices";
  - `denies the clay content its class states` → "nega o teor de argila que a própria classe afirma, o que é falso";
  - a tip grounding did not support → "os documentos citados não sustentam esta dica".
- A tip text longer than 300 characters is cut to 300 in its line, so the lines cannot push a batch past `PROMPT_CHAR_CEILING`.
- `OllamaClient.generate_cell` renders the lines in the prompt's `{{rejected}}` slot, after the documents:

  ```
  Sua resposta anterior foi recusada. Não repita estas dicas: corrija o motivo ou escreva outra que os documentos sustentem.
  - "<tip>": <reason>
  ```

  With no lines, the slot is empty.
- Each attempt is told only what the attempt before it lost. A batch's first attempt is told nothing, and so is the first attempt of every other batch.
- When an attempt has refused tips, grounding is not asked (SPEC 0160), so only the refused tips are named. The tips that were not checked are not reported as rejected.
- `rejections` records what it records today. The run manifest does not change.
- **The prompt.** The citation rule becomes: "Cite os documentos só no campo `"citations"`, pelos índices. No texto da dica, nunca escreva o índice nem o nome de um documento." The generate prompt moves to version 7.
- `max_attempts` stays 2.
- **No rebuild here.** A new prompt version splits the set, and the release refuses mixed prompt versions (SPEC 0227). The bundled corpus therefore stays as SPEC 0234 releases it. The rebuild runs once, after the crop, season and phase spec, on prompt version 7 or later.

## Alternatives Considered

- **Raise the temperature or change the seed on a retry.** Rejected. The answer would change at random rather than for the reason, and a run would no longer repeat on another machine.
- **Raise `max_attempts` to 3.** Rejected for now. A told retry is what changes the answer; a third attempt doubles the cost of a batch that will not ground, on a build that runs about 1.5 minutes per call. It can be raised later from the run manifests.
- **Tell the retry every earlier attempt's tips.** Rejected. With two attempts, it is the same; with more, the list grows, and the last attempt's tips are the ones the model repeats.

## Scope

- Includes:
  - `corpus/src/pipeline.py`: the reasons, the cut and `_build_batch`'s loop;
  - `corpus/src/llm.py`: `OllamaClient.generate_cell`;
  - `corpus/prompts/generate.md`: the citation rule, the `{{rejected}}` slot and version 7;
  - `corpus/tests/test_pipeline.py` and `corpus/tests/test_llm.py`.
- Does NOT include:
  - the refusal checks themselves (SPEC 0160, SPEC 0229, SPEC 0230) and the grounding check;
  - a rebuild or a release of the corpus;
  - the app.

## Acceptance Criteria

- `corpus/tests/test_pipeline.py`:
  - `test_a_retry_is_told_why_its_tip_was_refused`: for each refusal cause, a batch whose first attempt carries one tip refused for it is generated again with one line: the tip in quotes and that cause's reason. Its first attempt is told nothing.
  - `test_a_retry_is_told_its_tip_was_not_supported`: a batch whose first attempt carries a tip grounding does not support is generated again with the line `"<tip>": os documentos citados não sustentam esta dica`.
  - `test_a_retry_names_only_the_refused_tips`: an attempt with one refused tip and one clean tip tells the next attempt only about the refused one.
  - `test_a_long_refused_tip_is_cut_in_its_line`: a refused tip of 400 characters appears in its line cut to its first 300.
  - `test_each_batch_starts_untold`: in a cell of two batches whose first batch was refused twice, the second batch's first attempt is told nothing.
  - `test_a_told_batch_fits_the_prompt_ceiling`: the generate prompt of a full batch, with four lines of 300-character tips and the longest reason, is under `PROMPT_CHAR_CEILING`.
  - The present tests pass unchanged, with the fakes taking `rejected`.
- `corpus/tests/test_llm.py`:
  - `test_the_rejected_tips_reach_the_generate_prompt`: `generate_cell` with one line sends a prompt holding "Sua resposta anterior foi recusada" and `- <line>`, after the documents.
  - `test_an_untold_prompt_names_no_refusal`: without lines, the prompt holds no "recusada" and no `{{rejected}}`.
  - `test_the_generate_prompt_keeps_citations_out_of_the_text`: the prompt holds 'só no campo `"citations"`' and "nunca escreva o índice nem o nome".
  - The tests pinning the generate prompt's version read "7".

## Reproducibility

Python 3.12. In `corpus/`, run `python -m pytest tests -q`. No model and no network.

## Risks and Assumptions

- **The model may still repeat the tip.** A 7B model told why can still write the same sentence. The retry then fails as it does today, and the cell abstains; nothing is worse than before.
- **A told model may drop a supported claim.** The line says to fix the reason or write another tip the documents support. A model that writes a weaker tip still meets the same checks.
- **The model's own text goes back into its prompt.** Only tip texts the model wrote are sent back, cut to 300 characters, and the prompt already treats what it reads as data.
- **Stacked on SPEC 0234.** This branch changes `_build_batch`, which SPEC 0234 introduces, so it merges after it.
