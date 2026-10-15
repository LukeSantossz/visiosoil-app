# SPEC: fix(corpus): derive a cell's limitations from what its sources cover

## Problem

A cell's `limitations` ship to the app as the model wrote them, with no check
at all. They are not only statements of scope. In #251's runs, a limitation
asserted soil facts: it "repeats the error" of the tip in one run, and
"contradicts it" in another. A tip goes through a verified-quote check (SPEC
0155) and the number rule (SPEC 0160). A limitation, which sits on the same
screen, goes through only the number rule.

## Design Decision

**The model no longer writes limitations. The build derives them from relevance
grading: for each management topic that no kept source was graded relevant to,
the cell states that its sources do not cover that topic.**

**Why derive rather than check.** A limitation is meant to say "what this
guidance cannot tell you" (`research-agent.md` §7, the output contract), and the
review checklist asks that "the limitations are the real ones, not boilerplate"
(§12.3, item 8). The verified-quote check
cannot ground that kind of statement, because a passage cannot quote what a
source leaves out. So checking model-written limitations would refuse exactly
the scope statements they exist for. Meanwhile the factual ones, the kind #251
found wrong, belong in tips, where grounding applies. The build already knows
each cell's real gaps: grading asks, for every topic's query, whether each
source is relevant. A topic no source passed is a gap the evidence shows, and
it is specific to the cell.

**What changes:**

- **Grading records coverage per topic.** `build_cell` grades every source
  against every topic's query. Today `any(...)` stops at the first relevant
  query, so it cannot tell which topics a source covers.
  - A source is kept when at least one topic found it relevant, as today.
  - A topic is covered when at least one kept source is relevant to it.
  - The cost: with T topics and S sources, grading makes up to T × S calls
    instead of stopping early. For the B1' cell that is at most 6 × 3 = 18
    local calls.
- **Limitations come from uncovered topics.** For each uncovered topic, in
  topic order, the cell carries one sentence: "As fontes consultadas não tratam
  de {topic}." A fixed table phrases them, not the model.
  - The topic names are the ones in `MANAGEMENT_TOPICS`, with two exceptions.
    "água" reads "do manejo da água", so it is not read as water itself. The
    last topic reads "do que a classe de textura implica e do que não implica".
  - "As fontes consultadas" rather than "desta célula": the app composes
    several layers into one result, and "célula" is the build's word, not the
    user's. The Developer chose this wording after review, on 2026-10-14.
  - A cell whose sources cover every topic carries no limitations.
  - An abstained cell keeps `limitations: []`, as today. Its abstention
    disclaimer already says it has no guidance.
- **The generate prompt (version 5)** stops asking for `limitations`. The JSON
  it asks for becomes `{"status": ..., "tips": [...]}`.
- **Model output.** `_require_generated_shape` no longer requires `limitations`.
  A `limitations` field the model sends anyway is ignored and never shipped, as
  `build_cell_payload` already ignores fields the contract does not name.
- **The number rule (SPEC 0160)** now applies to tips only. Derived limitations
  hold no numbers by construction.
- **`BuildOutcome` gains `coverage`:** a mapping from each topic to the URLs
  graded relevant to it. The run manifest writes it as `"coverage"`, so a judge
  can see why a limitation was stated.

## Alternatives Considered

- **Ground each limitation as a tip is grounded.** Rejected. A scope statement
  ("as fontes não tratam de irrigação") has no passage to quote, so the check
  would refuse the limitations that are true. That is what SPEC 0161's Scope
  recorded.
- **Have the model label each limitation as scope or fact, and ground only the
  facts.** Rejected. The label is itself unchecked model output. A fact
  labelled "scope" would skip the check, and that is the failure this spec
  closes.
- **Keep model-written limitations and leave them to the human review (B4).**
  Rejected. B4 has no reviewer yet, and the app already reads `assets/corpus/`
  once a cell is promoted. An unchecked statement on the screen is the risk
  SPEC 0155 closed for tips.
- **Keep grading's early stop and infer coverage from the topics already
  graded.** Rejected. Stopping early leaves a source's other topics unknown, so
  the derived limitations would claim gaps that do not exist.

## Scope

- Includes:
  - `corpus/src/pipeline.py`:
    - grading every source against every topic;
    - the per-topic coverage;
    - the derived limitations and their phrase table;
    - `BuildOutcome.coverage`;
    - `_require_generated_shape` without `limitations`;
    - the number rule on tips only.
  - `corpus/prompts/generate.md`: version 5, with no `limitations` asked.
  - `corpus/src/manifest.py` and `corpus/src/probe.py`: `coverage` in the run
    manifest.
  - Tests in `corpus/tests/`.
- Does NOT include:
  - The cell contract (`cell.py`), the app, or how the app composes and
    de-duplicates limitations across layers.
  - The topics, the transform, grade and ground prompts, the grading threshold,
    the sources or the model.
  - Any other kind of limitation, such as source age or regional gaps.
    `research-agent.md` lists those for `alerts`, and they get their own spec
    when a source carries a date.
  - The abstained cell's text.

## Acceptance Criteria

- `a_topic_no_source_covers_becomes_a_limitation`: with sources relevant only to
  "fósforo" and "calagem", the grounded cell's limitations name the other four
  topics, in topic order, with the fixed phrasing.
- `a_cell_whose_sources_cover_every_topic_has_no_limitations`.
- `grading_asks_every_topic_of_every_source`: with three sources, the grader is
  called 6 × 3 times, and a source relevant only to its last topic is kept.
- `the_models_limitations_are_ignored`: a generation carrying `limitations`
  ships only the derived ones, and a generation without `limitations` is
  accepted.
- `an_abstained_cell_has_no_limitations`: unchanged behaviour, still pinned.
- `the_number_rule_reads_tips_only`: a model limitation stating a number no
  longer rejects the attempt, because it is ignored.
- `the_manifest_writes_the_coverage`: `RunManifest.to_json()["coverage"]` maps
  each topic to the URLs graded relevant to it, and the probe passes the
  outcome's.
- `the_generate_prompt_no_longer_asks_for_limitations`: the generate prompt is
  version 5, and its reply format has no `limitations`.
- `python -m pytest tests -q` in `corpus/` and `mf check` pass.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q   # Python 3.12 with corpus/requirements.txt; no model, no network
```

The B1' run after this records prompt versions transform 3, grade 2, generate 5
and ground 2.

## Risks and Assumptions

- **Assumption: "not graded relevant" means "not covered".** The grader can
  miss a source that does cover a topic, as it once dropped CT 33 for one
  wording of the query (SPEC 0153, SPEC 0154). Then the limitation understates
  the evidence. It never overstates it: a stated gap is at worst too cautious,
  and the probe's `coverage` shows which grades produced it.
- **Risk: more grading calls.** Up to T × S calls instead of fewer. That is 18
  for the B1' cell, on a local model.
- **Risk: SPEC 0160's limitation rule changes meaning.** The number rule on
  limitations, re-approved on 2026-10-14, guarded model-written text. With none
  shipped, it has nothing left to guard, so it narrows to tips. This needs the
  Developer's approval, since it touches what they re-approved.
- **Merge order:** this builds on #385 (SPEC 0161) and #384 (SPEC 0160), and
  merges after them.
