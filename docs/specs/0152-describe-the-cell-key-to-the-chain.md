# SPEC: fix(corpus): describe the cell key to the chain in plain words

## Problem

The chain that builds a substance cell is handed the cell's key, such as
`Argilosa|tb_oxidic`, and nothing else. `build_cell` passes that string to the
transform step as the question and to the generate step as the "Chave". Neither
prompt says what `tb_oxidic` means.

On 2026-10-09 the B1' re-probe (#251) returned "not worth reading" for that cell.
A rerun of relevance grading on the same sources, model and seed found why the
phosphorus circular (CT 33) was dropped:

- **The transform step only reordered the key.** Its three queries were
  `argilosa tb_oxidic textura`, `tb_oxidic argilosa atividade` and
  `textura argilosa tb_oxidic propriedades`. None names a management topic, and
  each carries the identifier `tb_oxidic`.
- **The grader answered `não` to CT 33 on all three**, and a document survives
  if any query grades it relevant. Doc 206 got `sim` three times, and CT 32 got
  `sim` twice.
- **The passage was not the cause.** CT 33 is 3,476 characters, under the
  6,000-character passage limit, and the clay-range critical levels are in what
  the grader read.
- **The grader is not broken.** Graded against hand-written queries in plain
  Portuguese, CT 33 got `sim` for "manejo da adubação fosfatada em solo argiloso
  de argila de baixa atividade" and for "nível crítico de fósforo Mehlich-1
  conforme o teor de argila". It got `não` for a third, generic one.

The same gap reaches the generator. The judged tip led with the 2:1, high-CEC
reading, while `tb_oxidic` is the low-activity family (`docs/architecture/research-agent.md`
§5.1). The generator was told only `tb_oxidic`.

## Design Decision

**The chain is told what the key means, in Portuguese, and the key's
identifiers stay out of its prompts.**

- `src/keys.py` gains `describe_key(key) -> str`. It returns a pt-BR phrase made
  of two parts:
  - The texture class: `Arenosa` → "textura arenosa", `Media` → "textura média",
    `Argilosa` → "textura argilosa", `Muito Argilosa` → "textura muito argilosa".
  - The clay-activity family, worded from §5.1's table:
    - `tb_oxidic` → "argila de atividade baixa (Tb, CTC da fração argila abaixo
      de 27 cmolc/kg), de solo muito intemperizado e oxídico".
    - `ta_less_weathered` → "argila de atividade alta (Ta, CTC da fração argila
      de 27 cmolc/kg ou mais), de solo menos intemperizado".
    - `intermediate` → "argila de atividade intermediária, entre a baixa (Tb) e
      a alta (Ta)".
  - For example, `Argilosa|tb_oxidic` becomes "solo de textura argilosa, com
    argila de atividade baixa (Tb, CTC da fração argila abaixo de 27 cmolc/kg),
    de solo muito intemperizado e oxídico".
  - A key whose class or family has no description raises `ValueError`. A
    corpus built for a class nobody described is wrong, so the build stops
    rather than falling back to the identifier.
- `build_cell` computes the description once and passes it, not the key, to
  `transform_queries` and `generate_cell`. The key still names the outcome, the
  cell and the run manifest.
- **Transform prompt, version 2.**
  - It receives the description instead of the key.
  - It asks for the queries in plain Portuguese, each about managing that soil
    or reading its lab report: liming, phosphorus, potassium, organic matter,
    water, and what the texture class does and does not imply.
  - It forbids identifiers and underscores.
- **Generate prompt, version 3.** The line `Chave: {{question}}` becomes
  `Solo: {{question}}`. Nothing else in it changes.
- **`_require_queries` refuses a query that carries an identifier.** That means
  a query containing `_` or `|`. The run stops with `ModelRefused`, as it
  already does for a blank query, because grading against identifiers is the
  failure this spec exists to stop.

## Alternatives Considered

- **Describe the key in the prompt templates only.** Rejected. The templates are
  shared by all twelve substance cells, so they would need the whole glossary,
  and the model would have to look its key up in it. A 7 B model doing that
  lookup is the kind of step that drifts. Doing it in code is deterministic and
  testable.
- **Hand-write the three queries per cell.** Rejected. This drops the transform
  step for 12 × 3 queries a person maintains. The step exists so that the
  literature's phrasing is reached from more than one angle (`QUERY_COUNT`).
- **Grade against the description as well as the queries.** Rejected. The
  description names no management topic, so on the evidence above it would not
  rescue CT 33. It would also add a fourth grading call per source.
- **Loosen the grader.** Rejected. The grader answered correctly when it was
  given readable queries.

## Scope

- Includes:
  - `corpus/src/keys.py`: `describe_key` and its two descriptions tables.
  - `corpus/src/pipeline.py`: the description passed to transform and generate,
    and the identifier guard in `_require_queries`.
  - `corpus/prompts/transform.md` at version 2, and `corpus/prompts/generate.md`
    at version 3.
  - Tests in `corpus/tests/test_keys.py` and `corpus/tests/test_pipeline.py`.
- Does NOT include:
  - The grade and ground prompts, the source manifest, the passage limit or the
    model.
  - The generate prompt's rule "Nunca doses, nunca níveis críticos". See Risks.
  - Rebuilding and judging the cell again. That is a run, recorded on #251 after
    this merges, not part of this change.
  - Any app (Dart) code.

## Acceptance Criteria

- `every_texture_class_is_described`: `describe_key` returns a description for
  every class `read_texture_classes()` reads from the shipped contract, crossed
  with every family in `CLAY_ACTIVITIES`.
- `the_description_names_the_family_in_words`: the description of
  `Argilosa|tb_oxidic` contains "textura argilosa" and "atividade baixa", and
  contains neither `tb_oxidic` nor `|`.
- `an_undescribed_key_fails_loudly`: an unknown class, an unknown family, or a
  key without `|` raises `ValueError`.
- `transform_and_generate_receive_the_description`: `build_cell` calls
  `transform_queries` and `generate_cell` with `describe_key(key)`, and the
  outcome's `key` is still the key.
- `a_query_carrying_an_identifier_is_refused`: a transform that returns a query
  containing `_` or `|` raises `ModelRefused`.
- `the_prompt_versions_moved`: `prompt_versions` reports transform `2` and
  generate `3`.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q
# Against a running Ollama with qwen2.5:7b pulled, after merge:
python -m src.probe --cell "Argilosa|tb_oxidic"
```

## Risks and Assumptions

- **Assumption: readable queries let CT 33 pass grading.** The control above
  shows the grader keeps it for two of three readable queries. Whether the
  transform step produces queries like those is a property of the model, which
  this change does not test. The rebuild on #251 measures it.
- **Risk: the generate prompt forbids the correction CT 33 carries.** It says
  "Nunca doses, nunca níveis críticos", and CT 33's clay-range Mehlich-1 levels
  are critical levels. If CT 33 is kept, the generator may still leave out what
  the B1' judgement asked for. Changing that rule is a decision about what a
  cell may say (ADR 0022), not a fix, so it is left out of this spec and flagged
  for the Developer.
- **Risk: a description that is too long or too specific steers the queries.**
  It is worded from §5.1's table only, and it adds no mineral (kaolinite) or soil
  order (Latossolo) the design did not state.
