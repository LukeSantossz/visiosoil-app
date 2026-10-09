# SPEC: fix(corpus): write one query per management topic

## Problem

SPEC 0152 gave the chain the meaning of the cell key, and the transform step now
writes readable queries. When the B1' cell (`Argilosa|tb_oxidic`) was rebuilt on
2026-10-09, the phosphorus circular (CT 33) was still graded `não` on all three
queries (#251):

1. "Como melhorar a fertilidade de um solo argiloso intemperizado com baixa
   atividade de argila?"
2. "Qual é a importância da matéria orgânica em solos argilosos oxídicos muito
   intemperizados?"
3. "Como a textura argilosa afeta a disponibilidade de nutrientes como fósforo e
   potássio em solos intemperizados?"

A diagnosis graded every source against those queries and two controls, under
three prompt layouts and with the author block cut. It found:

- **The grader works.**
  - It rejected the off-topic control ("criação de gado leiteiro e manejo da
    ordenha") on every source and layout.
  - It kept CT 33 for the phosphorus control ("nível crítico de fósforo
    Mehlich-1 conforme o teor de argila") in every layout.
- **The layout is not the cause.**
  - CT 33's verdicts were the same in every layout and with the author block cut.
  - Moving the query after the document made the gypsum circular (CT 32) worse.
- **The cause is coverage.** The grader matches topics, and CT 33 has one:
  phosphorus fertilisation by clay range. The three free queries are broad
  questions about fertility, and none of them is about phosphorus fertilisation.
  A narrow, correct source fails against all three.

Asking for "different angles" leaves the angles to the model. Nothing makes
any query reach a given topic, so whether a narrow source survives is luck.

## Design Decision

**The topics are fixed in code, and the transform step writes one query for each
of them.**

- `src/pipeline.py`: `MANAGEMENT_TOPICS` replaces `QUERY_COUNT`. It holds the six
  topics transform prompt version 2 already lists, in that order:
  1. "calagem"
  2. "fósforo"
  3. "potássio"
  4. "matéria orgânica"
  5. "água"
  6. "o que a classe de textura implica e o que não implica"
- **The client method changes.** `LLMClient.transform_queries(question, *, count)`
  becomes `transform_query(question, *, topic) -> str`. It returns one query
  about one topic.
- `build_cell` calls `transform_query` once per topic, in order, with the key's
  description. Two things do not change:
  - `_require_queries` still guards the list. It refuses a count other than one
    per topic, a blank query, and a query that carries an identifier.
  - The grading rule is the same. A document is kept if any query grades it
    relevant. Each source is now graded against up to six queries rather than
    three.
- **Transform prompt, version 3.**
  - It receives the soil's description and one topic.
  - It asks for one query, in plain Portuguese, about managing that soil or
    reading its lab report with regard to that topic.
  - It keeps version 2's ban on identifiers, codes and underscores.
  - It answers `{"query": "..."}`.
- `OllamaClient.transform_query` refuses with `ModelRefused` a reply whose
  `query` is missing or is not a non-blank string. A list where one string was
  asked for is refused too, not cut to its first item.

## Alternatives Considered

- **One transform call that returns a query per topic, keyed by topic.**
  Rejected. It saves five calls of the cheapest step, but a 7 B model would have
  to echo six keys, accents included. A mis-keyed reply would then need its own
  refusal rule. One call per topic makes coverage hold by construction.
- **Grade each source against the topics themselves, with no transform step.**
  Rejected. The design keeps a transform step (`research-agent.md` §5, "multi-query
  per cell", and SPEC 0071's `query_transform_produces_more_than_one_query`). A
  bare topic word is also a weaker query than a sentence that names the soil.
- **Leave grading as it is.** Rejected. Under it, CT 33 survives only when a
  query happens to name phosphorus fertilisation. That makes the corpus a
  property of the model's phrasing on the day.
- **Add a topic for reading the lab report.** Left out. Version 2 framed the
  queries as being about managing the soil "or reading its lab report", but did
  not list that as a topic. Each query's framing still says it, and the lab-report
  guide (Doc 206) passed every broad query.

## Scope

- Includes:
  - `corpus/src/pipeline.py`:
    - `MANAGEMENT_TOPICS`.
    - The `LLMClient.transform_query` protocol method.
    - The per-topic loop in `build_cell`.
    - `_require_queries` counting against the topics.
  - `corpus/src/llm.py`: `OllamaClient.transform_query`, replacing
    `transform_queries`.
  - `corpus/prompts/transform.md` at version 3.
  - Tests in `corpus/tests/test_pipeline.py` and `corpus/tests/test_llm.py`.
- Does NOT include:
  - The grade, generate and ground prompts, the source manifest, the passage
    limit or the model.
  - The generate prompt's rule "Nunca doses, nunca níveis críticos". See Risks.
  - Rebuilding and judging the cell again. That is a run, recorded on #251.
  - Any app (Dart) code.

## Acceptance Criteria

- `every_topic_gets_its_own_query`: `build_cell` calls `transform_query` once for
  each entry of `MANAGEMENT_TOPICS`, in order. Each call receives
  `describe_key(key)` and that topic. The outcome's `queries` are the returned
  queries in topic order.
- `a_document_relevant_to_one_topic_is_kept`: a source the grader keeps for the
  phosphorus query alone, and rejects for every other query, reaches generation.
- `the_topic_reaches_the_prompt`: `OllamaClient.transform_query` sends a prompt
  containing both the description and the topic, and returns the reply's
  `query`.
- `a_reply_without_one_query_is_refused`: `transform_query` raises `ModelRefused`
  in each of these cases:
  - the `query` field is missing;
  - it is blank;
  - it is not a string;
  - it is a list.
- `the_topics_are_the_ones_version_2_listed`: `MANAGEMENT_TOPICS` is the six
  topics above, in that order, with no duplicate.
- `the_query_guard_still_holds`: a transform that yields a blank query, or a
  query containing `_` or `|`, still raises `ModelRefused`.
- `the_transform_prompt_version_moved`: `prompt_versions` reports transform `3`.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q
# Against a running Ollama with qwen2.5:7b pulled:
python -m src.probe --cell "Argilosa|tb_oxidic"
```

## Risks and Assumptions

- **Assumption: the query written for "fósforo" is one the grader keeps CT 33
  for.** The diagnosis shows it keeps CT 33 for a query that names phosphorus
  levels by clay content. Whether the transform step writes such a query is a
  property of the model, and the rebuild on #251 measures it.
- **Risk: more documents pass.** Six topics keep any source that is relevant to
  one of them, and that is the intent. A cell that keeps more sources sends a
  longer generation prompt. The prompt ceiling already refuses one that is too
  long, before it is sent.
- **Cost.** Each cell makes up to 6 transform calls, up from 1, and up to 6
  grading calls per source, up from 3. With three sources that is at most 24
  calls before generation, against 10 before. On this machine a call takes about
  15 s, so a cell takes about six minutes before generation. The build is local
  and once per corpus release (ADR 0023).
- **Risk: the generate prompt forbids the correction CT 33 carries.** It says
  "Nunca doses, nunca níveis críticos", and CT 33's clay-range Mehlich-1 levels
  are critical levels. If CT 33 is now kept, the generator may still leave out
  what the B1' judgement asked for. That rule is an ADR 0022 decision, not a fix.
  It stays out of this spec, as it did in SPEC 0152.
