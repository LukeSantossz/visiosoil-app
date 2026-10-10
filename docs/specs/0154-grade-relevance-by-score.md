# SPEC: fix(corpus): grade relevance by a score

## Problem

SPEC 0153 writes one query per management topic. When the B1' cell
(`Argilosa|tb_oxidic`) was rebuilt on 2026-10-09, the phosphorus circular (CT 33)
was still graded `não` on all six queries (#251). The phosphorus query was:

> Como manejar o solo argiloso, de baixa atividade argilosa e muito
> intemperizado, em relação à disponibilidade de fósforo?

The grader was then given four more ways of asking about phosphorus. It kept
CT 33 for all four:

- "Como manejar a disponibilidade de fósforo em solo argiloso?"
- "Como manejar a adubação fosfatada em um solo argiloso, de baixa atividade
  argilosa e muito intemperizado?"
- "Como manejar a adubação fosfatada em solo argiloso?"
- "fósforo"

So the topic now reaches the grader, but whether CT 33 is kept depends on how
the query is worded. The grader answers one `sim` or `não` at temperature 0, so
a source on the edge of a query falls on one side or the other with nothing in
between.

A second diagnosis graded every source against the six topic queries, the four
phosphorus wordings and an off-topic control. It used two new prompts. Both
asked for a score from 0 to 3 on this scale:

- 0 — the document does not treat the query's subject;
- 1 — it mentions the subject only in passing;
- 2 — it treats the subject, but not the case the query describes;
- 3 — it treats the query's subject directly.

One prompt asked for the score alone. The other asked for a `sim`/`não`
verdict beside the score.

| Source | Score alone | Verdict and score |
| --- | --- | --- |
| CT 33, the written phosphorus query | 2 | `não`, 1 |
| CT 33, the four other phosphorus wordings | 2, 2, 3, 3 | `sim` on all four |
| CT 33, the other five topics | 0 | `não` |
| Lab-report guide (Doc 206), the six topics | 2 on five of them, 1 on calagem | `sim` on phosphorus and potassium only |
| Gypsum circular (CT 32), the six topics | 2 on calagem and água, 0 on the rest | `sim` on the same two |
| Off-topic control ("criação de gado leiteiro e manejo da ordenha") | 0 on all three sources | `não`, 1 on all three |

A third run graded three agronomic documents that are outside this cell's case
against the six topic queries. It used the score-alone prompt and the current
`sim`/`não` prompt:

- integrated pest management in soybean;
- drying and storing maize;
- managing sandy soils (Neossolos Quartzarênicos), which cover the same topics
  for the wrong soil.

All three scored 0 on every query, and the current prompt said `não` to every
one.

What the runs show:

- **The score alone keeps CT 33 for every phosphorus wording.** With a
  threshold of 2, CT 33 passes all five. The current prompt passes four.
- **The verdict adds nothing to the score.** Every `sim` came with 2 or 3, and
  every `não` with 0 or 1. Asking for both also lowered the score in three
  cases, including CT 33 on the written phosphorus query (2 to 1). That prompt
  would still drop CT 33.
- **A threshold of 2 admits nothing off-topic in these runs.** The off-topic
  query and all three off-case documents score 0, the sandy-soil document
  included.

## Design Decision

**The grader gives a score from 0 to 3, and a document is relevant to a query
when its score is 2 or more.**

- **Grade prompt, version 2.** It keeps version 1's framing: the grader is
  external and light, judges relevance not quality, and does not write the
  answer. It gives the 0–3 scale above and asks for the number alone.
- `src/llm.py` gets `parse_score(raw) -> int`. It reads one digit, 0 to 3,
  surrounded by any prose or punctuation. It raises `ModelRefused` in each of
  these cases:
  - the reply holds no digit;
  - it holds more than one number ("2 ou 3", "2/3", "10");
  - its number is outside 0–3.

  A hedge between two scores is refused rather than resolved, for the same
  reason `parse_yes_no` refuses "sim e não": picking one would turn the model's
  hedge into a decision nobody made.
- `src/llm.py` gets `RELEVANCE_THRESHOLD = 2`.
  `OllamaClient.grade_document` returns `parse_score(raw) >= RELEVANCE_THRESHOLD`.
- **Nothing else moves.**
  - The `LLMClient` protocol still returns a `bool` from `grade_document`, so
    `build_cell` and the rule "a document is kept if any query grades it
    relevant" are unchanged.
  - `parse_yes_no` stays, because the grounding check still answers `sim` or
    `não`.

## Alternatives Considered

- **A verdict beside the score, as JSON.** Rejected on the measurement. The
  verdict always agreed with the score, so it carried no information. Asking for
  both lowered the score on the very case this spec is for. It would also add a
  disagreement rule: what to do when `sim` comes with 1.
- **A threshold of 3.** Rejected. It drops CT 33 on the written phosphorus
  query (2) and on two of the other wordings. It also drops the lab-report guide
  and the gypsum circular, which score at most 2 on every topic, so the cell
  would keep nothing.
- **A threshold of 1.** Rejected. It would keep any document that mentions a
  topic in passing, and each source is graded against six queries.
- **Change the "fósforo" topic to "adubação fosfatada".** Rejected. It would fit
  the topic list to one document, and the next narrow source would need its own
  change.
- **Keep `sim`/`não` and add more wordings per topic.** Rejected. It multiplies
  the grading calls, and it still decides an edge case by luck.

## Scope

- Includes:
  - `corpus/prompts/grade.md` at version 2.
  - `corpus/src/llm.py`:
    - `parse_score`;
    - `RELEVANCE_THRESHOLD`;
    - `OllamaClient.grade_document` reading the score.
  - Tests in `corpus/tests/test_llm.py`.
- Does NOT include:
  - The transform, generate and ground prompts, `MANAGEMENT_TOPICS`, the source
    manifest, the passage limit or the model.
  - Recording each score in the probe report.
  - The generate prompt's rule "Nunca doses, nunca níveis críticos". See Risks.
  - Rebuilding and judging the cell again. That is a run, recorded on #251.
  - Any app (Dart) code.

## Acceptance Criteria

- `a_score_at_or_above_the_threshold_is_relevant`: `grade_document` returns
  `True` for a reply of `2` or `3`, and `False` for `0` or `1`.
- `a_score_is_read_through_prose`: `parse_score` reads `2`, `"Nota: 3."`,
  `" 0 "` and `"**1**"` as 2, 3, 0 and 1.
- `a_reply_without_one_score_is_refused`: `parse_score` raises `ModelRefused`
  for each of these replies: `""`, `"sim"`, `"talvez"`, `"2 ou 3"`, `"2/3"`,
  `"4"`, `"10"`, `"-1"`, `"-3"` and `"−2"` (with a Unicode minus sign). A
  negative number is outside 0–3, and read without its sign `-3` would pass
  as 3.
- `the_scale_reaches_the_prompt`: the prompt `grade_document` sends contains the
  query, the document and the four scale steps.
- `the_grade_prompt_version_moved`: `prompt_versions` reports grade `2`.
- `the_threshold_is_two`: `RELEVANCE_THRESHOLD == 2`.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q
# Against a running Ollama with qwen2.5:7b pulled:
python -m src.probe --cell "Argilosa|tb_oxidic"
```

## Risks and Assumptions

- **Risk: CT 33 passes at the threshold, not above it.** On the written
  phosphorus query it scores exactly 2. At temperature 0 with a fixed seed that
  is deterministic on this machine and this model digest, but a different model
  could put it at 1. The rebuild on #251 measures it. A model change already
  invalidates the run manifest (ADR 0023).
- **Assumption: the off-case documents stand in for real ones.** The three
  off-case documents were short texts written for the diagnosis. A real
  off-case source is longer and mentions more topics in passing, which is what
  step 1 of the scale is for.
- **Risk: more documents pass.** The lab-report guide scores 2 on five of the
  six topics, and it was already kept. Under the current prompt it passed two.
  A cell that keeps more sources sends a longer generation prompt, and the
  prompt ceiling already refuses one that is too long before it is sent.
- **Cost.** Unchanged. One grading call per source and query, as before.
- **Risk: the generate prompt forbids the correction CT 33 carries.** It says
  "Nunca doses, nunca níveis críticos", and CT 33's clay-range Mehlich-1 levels
  are critical levels. If CT 33 is now kept, the generator may still leave out
  what the B1' judgement asked for. That rule is an ADR 0022 decision, not a fix.
  It stays out of this spec, as it did in SPECs 0152 and 0153.
