# SPEC: fix(corpus): wait long enough for a whole-passage quote

## Problem

The corpus build cannot finish the Muito Argilosa cell of SPEC 0234, because the client gives up on a model answer that is valid but long.

- **What happens.** `_post` in `corpus/src/llm.py` waits 300 s for a model reply. Four runs of the cell on 2026-10-31 stopped with `TimeoutError` on the same grounding check, a 2870-token prompt at temperature 0.
- **What the model was writing.** The prompt was captured and replayed without a client timeout. The model answered with valid JSON, `"sustenta": "sim"`, quoting a whole passage of about 2300 characters. That is 885 tokens and took 409 s on the Iris Xe (2.16 tokens/s). The answer is what the check asks for: the claim's support is the passage's last sentence, and the model copied the passage up to it.
- **Why 300 s is not enough.** The grounding prompt asks the model to copy the supporting passage word for word, and a passage may hold `PASSAGE_CHAR_LIMIT` (6000) characters. At `MIN_CHARS_PER_TOKEN` (2), the floor the context budget already uses, that is up to 3000 tokens, or 1500 s at 2 tokens/s. The 300 s figure has no derivation, and it fits only a quote of about 650 tokens.
- **Decision.** Per the standing rule to fix each defect as it is found, the Developer approved this spec on 2026-10-31, ahead of finishing SPEC 0234.

## Design Decision

**A model call waits as long as copying a whole passage takes at the slowest rate the build has measured: `PASSAGE_CHAR_LIMIT // MIN_CHARS_PER_TOKEN // SLOWEST_TOKENS_PER_SECOND` seconds, 1500 s.**

- `SLOWEST_TOKENS_PER_SECOND = 2` is a new constant in `llm.py`. Its docstring records the 2.16 tokens/s measured for `qwen2.5:7b` on the Iris Xe.
- `MODEL_TIMEOUT_SECONDS` is derived from the three constants, so raising the passage limit raises the wait with it.
- `_post` passes `MODEL_TIMEOUT_SECONDS` to `urlopen`. `_get` and the source fetch keep their 60 s, since neither waits for a model.
- No answer changes. Every call that finished under 300 s finishes the same way, and the model, seed, prompts and `num_ctx` are untouched, so cells already built stay valid.

## Alternatives Considered

- **Cap the answer with `num_predict`.** Rejected: the long answer is correct. A cap cuts the JSON, the check refuses it, and the claim loses grounding it has.
- **Raise the timeout to a round number such as 900 s.** Rejected: it would be as underived as 300 s. A 6000-character quote still overruns it at the measured rate.
- **Retry on timeout.** Rejected: at temperature 0 and a fixed seed, a retry writes the same answer and times out the same way. All four runs did.

## Scope

- Includes:
  - `corpus/src/llm.py`;
  - `corpus/tests/test_llm.py`.
- Does NOT include:
  - the grounding prompt, which keeps asking for a verbatim quote;
  - the Muito Argilosa cell and the corpus release, which SPEC 0234 builds once this merges.

## Acceptance Criteria

- `corpus/tests/test_llm.py`:
  - `test_a_model_call_waits_long_enough_to_quote_a_whole_passage`: `_post` passes `MODEL_TIMEOUT_SECONDS` to `urlopen`, and that equals `PASSAGE_CHAR_LIMIT // MIN_CHARS_PER_TOKEN // SLOWEST_TOKENS_PER_SECOND`;
  - `test_the_wait_covers_the_measured_long_quote`: `MODEL_TIMEOUT_SECONDS` is more than the 409 s the replayed answer took.

## Reproducibility

Python 3.12. In `corpus/`, run `python -m pytest tests -q`. The replay used the captured payload against `qwen2.5:7b` on Ollama, with `stream` on and no client timeout. It finished with `done_reason: stop`, `eval_count: 885` and `eval_duration` 409 s.

## Risks and Assumptions

- **A truly stuck call now takes 25 minutes to fail, not 5.** The build runs offline and unattended, and a hang is rare next to the slow answers this fixes.
- **The rate is this machine's.** A slower one may need a lower `SLOWEST_TOKENS_PER_SECOND`, and the constant is where that goes.
