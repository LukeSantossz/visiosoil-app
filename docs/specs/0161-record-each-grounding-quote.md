# SPEC: fix(corpus): record the passage each grounding check quoted

## Problem

The grounding check makes the model copy, word for word, the passage that
supports a tip (SPEC 0155), and then throws the passage away. The person who
judges a probe run (#251) sees the tip and its citation index, but not which
sentence of the source was taken to support it. So they have to search the
source by hand, and that is the check SPEC 0160's Risks leaves to them: whether
a directional tip matches the numbers it was drawn from.

## Design Decision

**The grounding step returns its verdict together with the passage it quoted.
`build_cell` keeps both for every tip it checks, and the run manifest writes
them out.**

- **`LLMClient.is_grounded(tip, cited_texts) -> bool` becomes
  `ground(tip, cited_texts) -> Grounding`.** `Grounding` is a small frozen
  dataclass in `pipeline.py` with three fields:
  - `supported: bool`, which is today's verdict, unchanged;
  - `quote: str`, the passage the model copied;
  - `found: bool`, whether that passage was found in the cited text.

  `OllamaClient.ground` computes exactly what `is_grounded` does today and keeps
  the parts. `supported` is the parsed `sustenta` verdict (only "sim" or "não"
  is accepted) and `found`, as before.
- **`BuildOutcome` gains `groundings`:** one entry per grounding call, in order,
  across attempts. Each entry is `{"attempt", "tip", "supported", "quote",
  "found"}`. The rejected attempts are recorded as well, because the passage
  that failed to support a tip is what a judge needs in order to see why.
- **`RunManifest` gains `groundings`, written as `"groundings"`.** The probe
  passes `outcome.groundings` in.
- **Nothing reaches the app.** The cell artifact does not change. The quotes go
  only into the run manifest, which is git-ignored output under `corpus/out/`.
  Copyright stays where it is: the manifest already holds each source's digest,
  and a quote is a passage of a document the allowlist already admits.

## Alternatives Considered

- **Keep `is_grounded -> bool` and store the last quote on the client.** Rejected.
  Hidden state on the client couples the pipeline to one implementation, and the
  protocol exists so a fake can satisfy it structurally.
- **Record only the quotes of the shipped cell.** Rejected. When a cell
  abstains, there is no shipped cell, and #251's last run abstained. Why a tip
  failed is half of what the judge reads.
- **Put the quotes in the cell artifact.** Rejected. The app does not read them,
  and the cell contract (`cell.py`) is what the app reads.

## Scope

- Includes:
  - `corpus/src/pipeline.py`: `Grounding`, the `LLMClient.ground` protocol
    method, and `BuildOutcome.groundings`, filled in the generate-and-check
    loop.
  - `corpus/src/llm.py`: `OllamaClient.ground` in place of `is_grounded`, with
    the same verdict.
  - `corpus/src/manifest.py`: `RunManifest.groundings` and its JSON.
  - `corpus/src/probe.py`: passing `outcome.groundings` to the manifest.
  - Tests in `corpus/tests/`: the fakes and the call sites move to `ground`.
- Does NOT include:
  - Any change to the grounding verdict, the ground prompt, or SPEC 0160's
    number rule. A tip refused for stating a number is not sent to grounding, so
    it records no quote; its rejection already names it.
  - Grounding the cell's `limitations`. A limitation usually says what the
    sources do not cover, which no passage can quote, so it needs a design of
    its own.
  - The cell artifact, `cell.py`, or any app code.

## Acceptance Criteria

- `grounding_returns_the_verdict_and_the_quote`: `OllamaClient.ground` returns
  `supported`, `quote` and `found` for these cases:
  - a supported quote that is found;
  - a "não" verdict;
  - a quote that is not found;
  - a blank quote, which is never found.

  `supported` equals what `is_grounded` returned for the same reply.
- `the_existing_grounding_tests_hold_through_ground`: every SPEC 0155 grounding
  test passes against `ground(...).supported`.
- `each_grounding_call_is_recorded_with_its_attempt`: a build whose first attempt
  is rejected and whose second grounds records one entry per tip checked, with
  `attempt` 1 and 2, `supported`, the quote and `found`.
- `an_abstained_cell_still_records_its_groundings`: a build that exhausts its
  attempts has its rejected groundings in `outcome.groundings`.
- `a_numeric_tip_records_no_grounding`: a tip refused for stating a number adds
  no entry.
- `the_manifest_writes_the_groundings`: `RunManifest.to_json()["groundings"]`
  carries each entry, and the probe passes the outcome's.
- `the_cell_artifact_is_unchanged`: the written cell has no grounding field.
- `python -m pytest tests -q` in `corpus/` and `mf check` pass.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q   # Python 3.12 with corpus/requirements.txt; no model, no network
```

## Risks and Assumptions

- **Assumption: the quote is worth reading even when `found` is false.** A
  passage the model invented is evidence of why a tip failed. It is recorded
  with `found: false`, and never presented as the source.
- **Risk: a manifest grows with long quotes.** The quote is the model's reply
  as given, and it is not cut. Only the evidence sent to the model is capped by
  `PASSAGE_CHAR_LIMIT`. Cutting the quote would hide part of what the judge
  reads, and the manifest is local, git-ignored output, so it is recorded
  whole.
- **Merge order:** this builds on #384 (SPEC 0160), whose loop it changes, and
  merges after it.
