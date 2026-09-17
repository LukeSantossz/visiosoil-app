# SPEC: feat(corpus): build one corpus cell end to end with a local model

## Problem

ADR 0023 moved the corpus build to local open-source models and recorded that the
quality gap against the paid path is **unmeasured** — no local model has ever been
run against a cell — so the whole delivery plan rests on an assumption nobody has
tested, and there is no pipeline to test it with.

## Design Decision

**Build `corpus/`, a Python package that runs the full CRAG chain over one cell,
and run it with Ollama.** Query transformation, source grading, generation with
citations and the grounding graders — all four, on the single cell
`Argilosa|tb_oxidic`, producing a cell in exactly the shape
`test/fixtures/corpus/corpus.json` fixes and a run manifest beside it.

The chain is CRAG-shaped for a reason the wiki records: **the grader is external
and light, plug-and-play rather than a capability of the generator**
(`rag-auto-corretivo.md`). That is what makes a 7–8 B local model adequate for the
grading steps, and it is why dropping the graders — the cheaper probe — would
measure the wrong thing.

**Sources are curated for substance and searched for the overlays** (Developer's
decision, 2026-09-17). This slice only builds a substance cell, so it only needs
the curated half: a committed manifest of source URLs that *is* the allowlist,
fetched and extracted at build time.

**Curated means a manifest of URLs, not a folder of PDFs.** The Developer chose a
curated set with a literal allowlist; this reads that as a committed list of
sources rather than committed binaries. The property that was wanted — no page
the build did not choose ever reaches the model — is identical, and it buys three
things binaries do not: no large files in git, a licence question that never
arises, and a run manifest that records each source's URL *and* the digest of
what was fetched, so a source that changes under us is visible rather than
silent.

**Nothing in this slice writes to `assets/corpus/`.** The probe's output goes to
`corpus/out/`, which is git-ignored. A cell becomes an asset only after the
review gate, which is B4 and blocked.

## Alternatives Considered

- **Generation only, without the graders.** Rejected by the Developer and for a
  reason worth recording: the graders are the part a small model is *most* likely
  to handle well and the part the design most depends on, so a probe that skips
  them measures prose quality and calls it pipeline feasibility.
- **Commit the source PDFs.** Rejected: large binaries in git, a licence question
  for each, and no protection a URL manifest plus a content digest does not give.
- **Use the search backend for the substance cell too.** Rejected per the
  Developer's decision: substance is where quality decides everything and where
  the source set is small and well known, so choosing the sources by hand is
  cheaper than filtering a search and removes the injection surface rather than
  narrowing it.
- **Use LangChain or LangGraph for the chain.** Rejected per ADR 0022 §20.4 and
  the wiki's own over-engineering signal: this is a bounded chain run 44 times
  offline. `llm.py` is an HTTP call to `localhost:11434`.
- **Embed the prompts in the code.** Rejected: the run manifest records a prompt
  version, and a prompt that lives in a string literal cannot be versioned
  separately from the code that sends it. They go in `corpus/prompts/`.
- **Let the probe write `assets/corpus/corpus.json` directly.** Rejected: it would
  put unreviewed generated guidance where the app loads reviewed guidance from,
  which is the one thing the whole design exists to prevent.
- **Make the LLM client a thin `requests` call with no seam.** Rejected: ADR 0023
  keeps `LLMClient` precisely so a funded rebuild switches vendor by
  configuration, and the seam is also what lets every pipeline test run without a
  model.

## Scope

- Includes:
  - `corpus/README.md`, `corpus/requirements.txt` — following `ml/`'s precedent.
  - `corpus/src/llm.py` — the `LLMClient` seam and its Ollama implementation.
  - `corpus/src/sources.py` — the curated manifest, fetching, text extraction,
    and the content digest.
  - `corpus/src/pipeline.py` — the four chain steps.
  - `corpus/src/cell.py` — the cell shape, matching the fixture's contract.
  - `corpus/src/manifest.py` — the run manifest ADR 0023 requires.
  - `corpus/prompts/` — one file per step, each carrying a version.
  - `corpus/sources/substance.manifest.json` — the curated allowlist.
  - `corpus/tests/` — every unit above, driven by a fake `LLMClient` and fixture
    documents, so the suite needs no model and no network.
  - `.github/workflows/ci.yml` — a `corpus-tests` job mirroring `ml-tests`.
  - `.gitignore` — `corpus/out/`.
- Does NOT include:
  - Running the probe against a real model, and the agronomist's judgement of the
    cell it produces. Those are acts, not code; this slice is what makes them
    possible.
  - The search backend for the 27 unit overlays. That is B2, and the manifest
    this slice defines is what it will extend.
  - Cross-family verification and the human review gate. B4, and blocked.
  - The other 43 cells. B2 enumerates them.
  - Any write to `assets/corpus/`, `lib/`, or `ml/`.

## Acceptance Criteria

Each becomes a test, written before its implementation. Every one runs without a
model and without a network.

**The source manifest is the allowlist**

- `a_source_outside_the_manifest_is_refused`: fetching a URL the manifest does not
  list raises, rather than being fetched and filtered afterwards.
- `the_manifest_records_a_digest_for_what_was_fetched`: the run manifest carries
  a content hash per source, so a source that changed is visible.
- `an_unreachable_source_fails_the_build`: a cell citing a source that could not
  be fetched is not produced with a missing citation.

**The chain**

- `query_transform_produces_more_than_one_query`: the step exists and its output
  is used, rather than the original question being passed through.
- `grading_drops_an_irrelevant_document`: a document the grader rejects does not
  reach generation.
- `grading_keeps_a_relevant_document`.
- `all_documents_rejected_produces_an_abstention`: not an empty cell and not a
  crash — the abstained shape the composition rule already defines.
- `generation_emits_citations_into_its_own_source_array`: indices are local to the
  cell, which is what the composer re-indexes.
- `a_citation_outside_the_source_array_fails_the_build`: §12.1's rule, enforced
  where the cell is produced rather than where it is read.
- `the_grounding_grader_rejects_an_unsupported_claim`: a generated tip whose
  citation does not support it fails rather than shipping.
- `a_rejected_generation_is_retried_then_abstains`: bounded, so the probe cannot
  loop.

**The cell**

- `the_produced_cell_matches_the_fixture_contract`: the cell parses through the
  same reader the app uses, so the build cannot emit a shape the app rejects.
- `the_cell_is_written_to_out_not_to_assets`: unreviewed output never lands where
  the app loads from.

**The run manifest**

- `the_manifest_records_the_model_and_the_prompt_versions`: what ADR 0023 replaced
  the spend ledger with, so a corpus that does not reproduce is visible.
- `the_manifest_records_the_seed`.

**Injection**

- `a_fetched_document_instructing_the_model_does_not_change_the_output_shape`:
  §12.4's fixture, not a live page — a document carrying an instruction is data,
  and the cell it produces still validates.

## Reproducibility

```bash
cd corpus
python -m pip install -r requirements.txt
python -m pytest tests/ -q          # no model, no network
```

The probe itself, which needs a model:

```bash
ollama serve                         # if not already running
ollama pull qwen2.5:7b
python -m src.probe --cell "Argilosa|tb_oxidic"
```

Verified present on the Developer's machine on 2026-09-17: Ollama serving on
`localhost:11434` with `qwen2.5:7b`, `qwen2.5:3b` and `nomic-embed-text`. Python
3.12, matching the `ml-tests` job.

## Risks and Assumptions

- **Assumption:** `qwen2.5:7b` can grade and generate well enough to pass the
  grounding step. This is the assumption the probe exists to test, and a negative
  result is a result: ADR 0023's plan says a judgement of "not worth reading"
  stops the plan before the other 43 cells are built.
- **Assumption:** the substance sources are reachable and their text extractable.
  The manifest fails the build on an unreachable source rather than producing a
  cell with a hole, so this fails loudly at first run.
- **Risk:** a local model produces fluent, well-cited and agronomically wrong
  guidance. No automated step catches that; the human review gate is what does,
  and it is blocked on a reviewer nobody has identified. The probe's whole point
  is to put one cell in front of an agronomist before the other 43 exist.
- **Risk:** the retry bound makes the probe abstain on a cell a larger model would
  have grounded, so the measurement reads worse than the design deserves. The run
  manifest records the retries, so the outcome is readable rather than a bare
  verdict.
- **Assumption:** determinism is achievable enough to be worth recording a seed.
  Ollama's sampling is seedable; the manifest records the seed and the model
  digest, and a rerun that diverges is itself a finding.
- **What would invalidate this spec:** a released budget. The `LLMClient` seam
  would be pointed at the paid provider and the curated-versus-searched split
  would be reconsidered, since `allowed_domains` enforces the allowlist at the
  platform there.
