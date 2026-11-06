# Corpus build

The offline half of the Research Agent: it builds the corpus the app composes
management tips from. Python 3.12, following `ml/`'s precedent — a
Python pipeline inside a Flutter repository.

The design is [ADR 0022](../docs/adr/0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md);
the provider decision is [ADR 0023](../docs/adr/0023-the-corpus-is-built-by-local-open-source-models-and-tier-2-leaves-v1.md);
the ordered backlog is
[`research-agent-implementation-map.md`](../docs/plans/research-agent-implementation-map.md).

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

**The code for the re-probe is built** (SPEC 0072), and building it found that the
first verdict was reached on less than it seemed. The model read each document
only up to its first 6,000 characters, which for the SciELO articles was a title,
the author affiliations and an abstract, and the server cut each prompt at a
context length chosen from the machine's video memory. So the fetcher now reads
PDF, a manifest entry names the pages of its passage, a passage longer than the
model reads is refused rather than cut, and every request pins its context. The
manifest holds three Embrapa passages.

**The twelve substance cells were built and released** (SPEC 0227): the four
texture classes by the three clay-activity families. They ship without the
agronomist's judgement and without B4's human review, by the Developer's
decision of 2026-10-28, and the land-use and unit cells are out of scope. The
implementation map records the runs and that decision.

**Every texture class now has a generic cell** (SPEC 0234): `<class>|generic`,
built from its own manifest of at least fifteen trusted passages, which is what
a record composes when no family cell holds tips for it. A family cell is built
only where a manifest for it exists in `corpus/sources/`, and today that is
`Argilosa|tb_oxidic`. The eight family cells that abstained in `2026.10.28.1`
left the corpus.

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
python -m src.probe --cell "Arenosa|generic"
```

The probe reads the manifest of its cell, `corpus/sources/<key>.manifest.json`
with `|` written `__` and a space written `-`, unless `--manifest` names another.

Output lands in `corpus/out/`, which is git-ignored. It reaches
`assets/corpus/`, where the app loads guidance from, only through the release.

## Releasing the corpus

```bash
python -m src.build_grids                          # the two IBGE lattices, in out/
python -m src.release --cells out/ --grids out/ --version 2026.10.31.1
```

The release expects a generic cell per texture class and a family cell for each
family manifest in `corpus/sources/`, reads them by their run manifests' keys and
refuses, naming the cause, a missing or extra key, a key two manifests name,
cells from two models or two sets of prompt versions, a cell the app's reader
would reject, or a grid of the wrong magic, kind or lattice. Nothing is written
unless all of it passes. It derives each biome's default clay-activity family
from the grids, and writes `corpus.json` and both grids into `assets/corpus/`,
which is tracked (SPEC 0227).

A tip QA or the Developer rejected is listed in `corpus/rejected_tips.json`,
one entry per claim: the `phrase` that identifies it, the cell it was found in,
the `reason` and the `reference` that rejected it. The release drops every tip
whose text, lowercased and with its spacing collapsed, contains a listed phrase,
in any cell, and prints each drop. A grounded cell left without tips is released
as the build's abstention, its sources and limitations kept. A list entry with a
blank phrase, reason or reference is refused, since a blank phrase would match
every tip. To keep a rejected claim out of every later release, add its entry
here rather than editing `assets/corpus/corpus.json` alone (SPEC 0262). The list
catches a claim that keeps its words, not one a rebuild rewords.

The cells are not reviewed by a person: `corpus.json` carries
`humanReview: false`, and every grounded cell carries the advisory disclaimer.

## How it is shaped

Four steps, CRAG-shaped: transform the key into several queries, grade each
document for relevance, generate a cited cell from what survived, check that
every tip is supported by what it cites. The grader is deliberately **external
and light** (`llm-wiki/wiki/rag-auto-corretivo.md`), which is what makes a 7-8 B
local model adequate for it.

Two boundaries carry the safety properties:

- **`sources.py` is the allowlist.** A URL the manifest does not list is refused
  before it is fetched, not filtered afterwards. ADR 0023 moved this enforcement
  out of a provider's platform and into this code. For a PDF the manifest also
  names the pages, so the passage is chosen by the same reviewed act as the
  source.
- **`cell.py` is the contract.** A page can persuade a model to emit anything; it
  cannot persuade this module to accept it. Every cell is rebuilt from the fields
  the contract names, so a field a source asked for is dropped rather than
  shipped.

Two runtime dependencies, both pure Python and both file-format readers:
**`pyshp`**, which reads the IBGE shapefiles the grids are rasterised from and
pulls no GDAL, and **`pypdf`**, which reads the Embrapa PDFs a substance cell
cites. Everything else is the standard library — `requirements.txt` says what
each entry is for.

Prompts live in `prompts/` rather than in string literals because the run
manifest records a prompt version.
