# SPEC: fix(corpus): ground a tip by a verified quote

## Problem

SPEC 0154 made the B1' cell (`Argilosa|tb_oxidic`) keep the phosphorus circular
(CT 33). The rebuild on 2026-10-10 then produced one tip citing CT 33 (#251):

> Em solos argilosos com baixa atividade de argila, a adubação fosfatada deve
> ser ajustada para alcançar 90% do rendimento potencial, indicando que a
> textura argilosa do solo não necessariamente requer doses mais altas de
> fósforo.

CT 33 does not say this:

- 80% and 90% of the potential yield define its critical phosphorus levels, for
  higher-risk and lower-risk systems. It does not tell anyone to adjust the
  fertilisation to reach 90%.
- It says nothing about whether clayey soil needs higher phosphorus doses.

The grounding check (ground prompt version 1) asks one question: "A evidência
sustenta a afirmação? Responda apenas `sim` ou `não`." It answered `sim`, so the
cell shipped as `grounded`.

A diagnosis ran three grounding prompts against CT 33 as the cell cites it (the
first 6,000 characters), on nine claims:

- the probe's tip and its limitation;
- two parts of the tip on their own;
- two claims that contradict CT 33;
- three claims CT 33 does make.

The three prompts were:

- **v1**, the current prompt;
- **strict**, v1 plus an instruction to answer `não` when any part of the claim
  adds a goal, number, conclusion or recommendation the evidence does not hold;
- **quote**, which asks the model to copy, word for word, the passage of the
  evidence that supports the claim, beside a `sim`/`não` verdict. The code then
  checks whether that passage is really in the evidence.

| Claim | Should be | v1 | strict | quote, checked |
| --- | --- | --- | --- | --- |
| The probe's tip | refused | **`sim`** | **`sim`** | refused: `sim`, passage not in CT 33 |
| The probe's limitation | refused | `não` | `não` | refused: `sim`, passage not in CT 33 |
| "deve ser ajustada para alcançar 90% do rendimento potencial" | refused | **`sim`** | **`sim`** | refused: `sim`, passage not in CT 33 |
| "não requer doses mais altas de fósforo" | refused | `não` | `não` | refused: `não` |
| "Solos argilosos dispensam adubação fosfatada" | refused | `não` | `não` | refused: `não` |
| "Pela resina, o nível crítico aumenta com a argila" | refused | `não` | `não` | refused: `não` |
| "Por Mehlich-1, o mesmo teor tem significado diferente conforme a argila" | accepted | `sim` | `sim` | accepted |
| "Pela resina, o nível crítico não depende da argila" | accepted | `sim` | `sim` | accepted |
| "Os níveis críticos são definidos para 80% e 90% do rendimento" | accepted | `sim` | `sim` | accepted |

What the runs show:

- **The verdict alone cannot be trusted on a paraphrase.** v1 and strict said
  `sim` to the probe's tip and to the "90%" claim. The strict wording changed no
  answer.
- **The model's passage can be checked, and its verdict cannot.** On the three
  claims that should fail, the quote prompt also said `sim`. Each time, the
  passage it gave was not in CT 33. Only its first 3 to 16 characters matched.
  For the tip and the limitation, the rest was the claim's own words.
- **The PDF's line breaks must be joined.** At first, one true claim failed. Its
  passage matched CT 33 for 607 of 904 characters and then wrote "potencial",
  where the extracted text has "poten- cial". With a hyphen and line break
  joined on both sides, all nine claims came out as they should.

## Design Decision

**A tip is grounded when the model says `sim` and quotes a passage that the
code finds in the cited evidence.**

- **Ground prompt, version 2.** It asks the model to copy, word for word, the
  passage of the evidence that supports the claim, and to copy nothing if the
  evidence does not say everything the claim says. It asks for one JSON object:
  `{"trecho": "...", "sustenta": "sim" ou "não"}`.
- `src/llm.py` gets `quote_in_evidence(quote, cited_texts) -> bool`.
  - It is `True` when the quote, normalised, appears in the normalised text of
    any cited document.
  - It searches only the part of each document the model saw: the first
    `PASSAGE_CHAR_LIMIT` characters.
  - A blank quote is never found.
  - To normalise means four steps on both sides: NFC form; a hyphen followed by
    whitespace between two word characters is joined ("poten- cial" becomes
    "potencial"); every run of whitespace becomes one space; and case is folded.
- `OllamaClient.is_grounded` returns `True` only when `sustenta` reads `sim`
  through `parse_yes_no` and `quote_in_evidence` finds `trecho`.
  - A `não` verdict is not grounded, whatever it quotes.
  - A `sim` whose passage is missing, blank or not in the evidence is not
    grounded. That makes it a rejection, which `build_cell` retries and then
    abstains on, as it does today.
  - A reply that is not a JSON object, whose `sustenta` is neither `sim` nor
    `não`, or whose `trecho` is not a string raises `ModelRefused`, as a
    malformed generation does.
- **Nothing else moves.**
  - The `LLMClient` protocol still returns a `bool` from `is_grounded`, so
    `build_cell` is unchanged.
  - The generate prompt keeps "Nunca doses, nunca níveis críticos". The
    Developer chose to make the check stricter and keep the advisory stance
    (`CONTEXT.md`, ADR 0022).

## Alternatives Considered

- **The strict wording, with a `sim`/`não` answer.** Rejected on the
  measurement. It gave the same answer as v1 on all nine claims, including the
  two it was written for.
- **The quote prompt, trusting its verdict.** Rejected on the measurement. It
  said `sim` to all three claims that should fail. Only the code's check of the
  passage refused them.
- **Compare the quote without joining line-break hyphens.** Rejected on the
  measurement. It refused a true claim because the model had joined
  "poten- cial".
- **Accept a quote that is close to the evidence (a similarity ratio).**
  Rejected. Two of the false passages were the claim's own words after a
  matching start, and a ratio threshold would have to tell a paraphrase from a quote,
  which is the judgement this spec takes away from the model.
- **Also ground the cell's `limitations`.** Not in this spec. A limitation says
  what the sources leave out, so by design it has no supporting passage, and
  this check would refuse every one. See Risks.
- **Allow critical levels in the generated tips.** Not chosen. It would change
  the advisory stance and needs an ADR 0022 amendment. The Developer declined it.

## Scope

- Includes:
  - `corpus/prompts/ground.md` at version 2.
  - `corpus/src/llm.py`:
    - `quote_in_evidence`;
    - `OllamaClient.is_grounded` reading the verdict and checking the quote.
  - Tests in `corpus/tests/test_llm.py`.
- Does NOT include:
  - The transform, grade and generate prompts, `MANAGEMENT_TOPICS`, the source
    manifest, the passage limit or the model.
  - Grounding the cell's `limitations`.
  - Recording each quote in the probe report.
  - Rebuilding and judging the cell again. That is a run, recorded on #251.
  - Any app (Dart) code.

## Acceptance Criteria

- `a_supported_claim_quoted_from_the_evidence_is_grounded`: a reply of
  `sim` with a passage taken from the cited text makes `is_grounded` return
  `True`.
- `a_quote_not_in_the_evidence_is_not_grounded`: a reply of `sim` whose
  passage is not in the cited text returns `False`.
- `a_não_verdict_is_not_grounded`: a reply of `não` returns `False`, even when
  its passage is in the cited text.
- `a_blank_quote_is_not_grounded`: a reply of `sim` with `""` or only spaces as
  its passage returns `False`.
- `a_quote_matches_across_a_line_break_hyphen`: a passage written "potencial"
  is found in evidence that reads "poten- cial", and a difference only in
  whitespace or case is found too.
- `a_quote_past_what_the_model_saw_is_not_found`: a passage that starts after
  the first `PASSAGE_CHAR_LIMIT` characters of the cited text is not found.
- `a_quote_from_any_cited_text_counts`: with two cited texts, a passage from the
  second is found.
- `a_malformed_grounding_reply_is_refused`: `is_grounded` raises `ModelRefused`
  for a reply that holds no JSON object, for `sustenta` set to `talvez`, and for
  `trecho` set to a number.
- `the_claim_and_evidence_reach_the_prompt`: the prompt `is_grounded` sends
  contains the claim, the cited text and the request for the passage.
- `the_ground_prompt_version_moved`: `prompt_versions` reports ground `2`.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q
# Against a running Ollama with qwen2.5:7b pulled:
python -m src.probe --cell "Argilosa|tb_oxidic"
```

## Risks and Assumptions

- **Risk: a supported paraphrase may be refused.** If the model cannot copy a
  passage word for word, a tip the evidence does support is refused. After two
  attempts the cell abstains. That costs coverage, not correctness, and it is
  the side ADR 0022 chooses: abstaining is honest. The rebuild on #251 measures
  it on the real cell.
- **Risk: a real passage that does not support the claim.** The code checks
  that the passage exists, not that it supports the claim. A model could quote a
  true but unrelated sentence and say `sim`. In the diagnosis, every `sim` with
  a real passage was on a true claim, but nine claims are a small sample.
- **Assumption: one source, nine claims.** The diagnosis ran on CT 33 alone.
  The lab-report guide and the gypsum circular were not quoted. Their text comes
  from the same PDF extraction, so the same line-break hyphens are expected.
- **Risk: limitations stay unchecked.** The probe's limitation repeats an
  unsupported claim ("não necessariamente implica em necessidade de doses mais
  altas de fósforo"), and nothing checks it. It is out of this spec's Scope,
  because a limitation by design has no supporting passage. How to check a
  limitation is a decision of its own.
- **Cost.** Unchanged: one grounding call per tip. The reply is longer, because
  it carries the passage.
