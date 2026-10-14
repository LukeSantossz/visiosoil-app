# SPEC: fix(corpus): state the relation a source shows, never its number

## Problem

The generate prompt asks for "what the texture class changes in reading the lab
report" and forbids critical levels in the same breath. For `Argilosa|tb_oxidic`,
CT 33 states that change only as critical levels by clay range. So the generator
paraphrases around the numbers, the grounding check rightly rejects the
paraphrase, and the calibration cell abstains (#251, SPEC 0155's run).

## Design Decision

**The generate prompt (version 4) asks for the direction the numbers show, never
the numbers. The build rejects any tip that states a number, the way it rejects
an ungrounded one.** The Developer chose this on 2026-10-12, over permitting
critical levels and over accepting the abstention.

**Why it fits the advisory stance.** `CONTEXT.md` and ADR 0022 forbid
prescribing a field action, and the prompt's rule against doses and critical
levels comes from that stance. A direction such as "under Mehlich-1, the
critical phosphorus level is lower the more clayey the soil, and the resin
figure barely depends on clay" prescribes nothing. It says how to read a number
the user already has, which is the purpose the prompt already states. No ADR
changes.

**What the source supports, measured on 2026-10-12.** The CT 33 passage the
model reads (3,476 characters, digest `337dbc61438a6672`, unchanged since
2026-09-22) carries both halves:

- **Resin:** one sentence states it in words: "A interpretação dos teores de P
  no solo avaliados pelo método da resina é pouco influenciada pelo teor de
  argila, não havendo necessidade, portanto, de criar classes em razão dessa
  variável."
- **Mehlich-1:** the sentence gives the critical levels against clay ranges:
  "18 mg dm-3, 15 mg dm-3, 8 mg dm-3 e 4 mg dm-3 para os solos com teor de argila
  ≤15%, 16% a 35%, 36% a 60% e >60%".

The grounding check (SPEC 0155) has the model quote the evidence word for word.
The quote may hold numbers; only the tip may not. So a directional tip can be
grounded by that sentence.

**The prompt, version 4.** The advisory rule becomes:

> O conteúdo é **consultivo**: o que a classe de textura NÃO significa e o que
> ela muda na leitura do laudo. Nunca doses e nunca números: nem níveis
> críticos, nem teores, nem percentuais. Quando um documento mostra a diferença
> por números, escreva a direção que os números mostram (por exemplo, se um
> nível crítico é maior ou menor nesta classe), não os números. Cite os
> documentos só pelos índices, nunca pelo nome.

Nothing else in the prompt changes.

**The build enforces it.** A prompt rule is one the model can ignore; this one
is checked in code.

- In `pipeline.build_cell`'s generate-and-check loop, a tip whose text states a
  number is rejected before grounding is asked.
- A tip states a number when it holds a run of digits, optionally with a decimal
  part, that is not glued to a preceding letter-and-hyphen name. So "18 mg dm-3",
  "90% do rendimento", "pH 5,5" and "CT 33" are numbers. "Mehlich-1" is a
  method's name and is not.
- The rejection is recorded as `states a number: <tip text>`, beside the
  ungrounded ones.
- As today, any rejection fails the attempt. The loop retries up to
  `max_attempts`, and then the cell abstains.
- The check lives in the pipeline, not in `cell.validate_cell`. A number is the
  model breaking the stance, which is retried, not a cell the app cannot read,
  which fails the build.

## Alternatives Considered

- **(b) Permit critical levels with the source cited.** Not chosen by the
  Developer. It changes the advisory stance and needs an ADR before a spec.
- **(c) Accept the abstention.** Not chosen. The corpus would stay empty exactly
  where the source carries the useful correction.
- **Enforce only in the prompt.** Rejected. SPEC 0155 showed that the model
  writes what the rule forbids, and that a code check is what stops it.
- **Reject inside `validate_cell`.** Rejected. That turns a model's slip into a
  build failure, where the loop's retry-then-abstain is the answer ADR 0022
  defines.
- **Forbid every digit.** Rejected. Method names such as "Mehlich-1" carry
  digits, and refusing them would refuse the tip CT 33 exists to support.

## Scope

- Includes:
  - `corpus/prompts/generate.md`: version 4, the advisory rule above.
  - `corpus/src/pipeline.py`: the number check in the generate-and-check loop.
  - Tests in `corpus/tests/test_pipeline.py` and `corpus/tests/test_llm.py`.
  - After merge, the B1' probe run on the machine that serves `qwen2.5:7b`, with
    the result recorded on #251. The run is the Developer's; the judgement of
    the cell is #251's.
- Does NOT include:
  - Any change to ADR 0022, `CONTEXT.md` or the advisory stance.
  - The transform, grade or ground prompts, the topics, the sources, the passage
    limit or the model.
  - Grounding the cell's `limitations` (SPEC 0155 Risks).
  - Number words ("dois", "metade"). They are rare in the prompt's domain, and a
    later run that finds one gets its own spec.
  - Any app code.

## Acceptance Criteria

- `a_tip_stating_a_number_is_rejected_then_abstains`: when every attempt yields
  a tip such as "18 mg dm-3", "90% do rendimento" or "pH 5,5", the cell
  abstains, and its rejections read `states a number: …`.
- `a_number_is_rejected_before_grounding_is_asked`: the grounding check is never
  called for a tip that states a number.
- `a_method_name_is_not_a_number`: a tip naming "Mehlich-1", with no other
  number, reaches grounding, and the cell is grounded when grounding passes.
- `a_numeric_tip_retried_into_a_directional_one_is_grounded`: a first attempt
  with a number and a second without one ends grounded on attempt 2.
- `the_generate_prompt_asks_for_the_direction_not_the_number`: the generate
  prompt is version 4, and the rendered prompt carries the direction rule.
- The existing corpus tests pass, and `python -m pytest tests -q` in `corpus/`
  is green.
- `mf check` passes.

## Reproducibility

```sh
cd corpus
python -m pip install -r requirements.txt   # Python 3.12
python -m pytest tests -q                   # no model, no network
# after merge, on the machine with the model:
ollama pull qwen2.5:7b
python -m src.probe --cell "Argilosa|tb_oxidic" --out <dir>
```

The probe pins `qwen2.5:7b`, seed 1234, and the prompt versions it records
(transform 3, grade 2, generate 4, ground 2).

## Risks and Assumptions

- **Assumption: the model can quote the Mehlich-1 sentence to ground a
  directional tip.** SPEC 0155 has it copy the passage word for word, and that
  sentence holds the clay ranges and their levels. If the model will not tie the
  direction to it, the cell abstains again, and the run says so.
- **Risk: a directional tip can be ungrounded and still read as grounded.** The
  check confirms that a supporting passage exists. It does not confirm that the
  stated direction matches the numbers. The probe does not record the quote
  (SPEC 0155's Scope), so the #251 judgement reads the tip against CT 33's
  passage, quoted above.
- **Risk: the regex misses a number written as a word, or a unit with no
  digit.** Recorded in Scope; the run's tips are read before any cell ships.
- **The judgement is still a person's.** This spec makes a grounded cell
  possible. Whether it is worth reading, and whether B3 proceeds, stays the
  #251 decision.
