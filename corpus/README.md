# Corpus build

The offline half of the Research Agent: it builds the reviewed corpus the app
composes management tips from. Python 3.12, following `ml/`'s precedent — a
Python pipeline inside a Flutter repository.

The design is [ADR 0022](../docs/adr/0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md);
the provider decision is [ADR 0023](../docs/adr/0023-the-corpus-is-built-by-local-open-source-models-and-tier-2-leaves-v1.md);
the ordered backlog is
[`research-agent-implementation-map.md`](../docs/architecture/research-agent-implementation-map.md).

## State

**Slice B1 — the calibration probe — is built and has been run.** The chain, the
source manifest, the cell contract, the run manifest, the Ollama client, the
grids and the overlay search all exist and are tested, and `corpus-tests` runs
them in CI.

**Its first real run produced a cell that is not worth reading** — true, cited,
grounded, and a methodological aside rather than the correction of a wrong
heuristic that a cell is supposed to be. The binding problem is which sources a
substance cell may cite, not the model.

**That decision was taken on 2026-09-18**: a substance cell cites Embrapa tier-1
extension material — Sistemas de Produção, Circulares Técnicas, Boletins — which
is what carries management recommendations, with SciELO demoted to corroboration.
Most of that material is PDF and this fetcher reads HTML, so the re-probe slice
**will add** `pypdf` alongside `pyshp` — it is not a dependency yet, and
`requirements.txt` is the authority on what is — and rebuilds and judges the same
cell again **before any of the other 43 is built**. The implementation map records the run, its verdict and the
re-probe slice.

## Running the tests

```bash
cd corpus
python -m pip install -r requirements.txt
python -m pytest tests/ -q      # no model, no network
```

## Running the probe

```bash
ollama serve                    # if not already running
ollama pull qwen2.5:7b
python -m src.probe --cell "Argilosa|tb_oxidic"
```

Output lands in `corpus/out/`, which is git-ignored. **It never lands in
`assets/corpus/`**: that is where the app loads *reviewed* guidance from, and
moving a cell there is the review gate's act — a gate blocked on a reviewer
nobody has identified.

## How it is shaped

Four steps, CRAG-shaped: transform the key into several queries, grade each
document for relevance, generate a cited cell from what survived, check that
every tip is supported by what it cites. The grader is deliberately **external
and light** (`llm-wiki/wiki/rag-auto-corretivo.md`), which is what makes a 7-8 B
local model adequate for it.

Two boundaries carry the safety properties:

- **`sources.py` is the allowlist.** A URL the manifest does not list is refused
  before it is fetched, not filtered afterwards. ADR 0023 moved this enforcement
  out of a provider's platform and into this code.
- **`cell.py` is the contract.** A page can persuade a model to emit anything; it
  cannot persuade this module to accept it. Every cell is rebuilt from the fields
  the contract names, so a field a source asked for is dropped rather than
  shipped.

One runtime dependency today: **`pyshp`**, which reads the IBGE shapefiles the
grids are rasterised from. The re-probe slice adds a second, `pypdf`, for the
reason under **State**; until that slice lands, this is the whole list. It is pure Python and pulls no GDAL. Everything else is the
standard library — `requirements.txt` says what each entry is for.

Prompts live in `prompts/` rather than in string literals because the run
manifest records a prompt version.
