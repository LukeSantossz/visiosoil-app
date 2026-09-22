# SPEC: feat(corpus): read the passage a curated pdf names and give the model all of it

## Problem

The re-probe the Developer decided on 2026-09-18 cannot run: the build reads HTML
only, and what it does read reaches the model cut short twice without a word —
each document at its first 6,000 characters, and each prompt at a context length
the local server picks from the machine's video memory.

Both cuts are measured, not inferred:

- **The first run never showed the model an article body.** Re-fetched on
  2026-09-22 through the build's own transport and extractor, the two SciELO
  sources that still answer are 42,213 and 40,462 characters long, and their
  introductions start at characters 9,660 and 8,280. `OllamaClient` sends
  `document.text[:6000]` to both the grader and the generator, so what the model
  summarised was a title, a list of author affiliations and an abstract. The
  first verdict — a methodological aside rather than guidance — is what an
  abstract of a measurement study yields, and that is not a finding about the
  sources' bodies, which were never read.
- **The prompt is cut to a length nobody chose.** `OllamaClient` sets no
  `num_ctx`, so the server applies its default. On this machine the server log
  records `vram-based default context total_vram="0 B" default_num_ctx=4096`. A
  generation prompt carrying two or three 6,000-character documents is longer
  than 4,096 tokens, and a machine with more video memory would get a larger
  default, so **the same model and seed see different prompts on different
  machines** — which the run manifest, whose whole purpose is reproducibility,
  cannot see.

A PDF makes the first cut worse rather than better. The Embrapa extension
material the Developer chose opens with a cover, a catalogue card, an editorial
board and a table of contents, so its first 6,000 characters carry no guidance
at all.

## Design Decision

**The manifest names the passage, and the model reads all of it.** Four parts,
each the smallest change that closes one cut:

1. **A PDF is read with `pypdf`, recognised by its magic bytes.** `http_transport`
   returns the body undecoded as `bytes` when it starts with `%PDF-`, and decoded
   `str` as today otherwise. `fetch_sources` sends `bytes` to a PDF extractor and
   `str` to the existing HTML extractor. The signature `%PDF-` decides, not the
   URL's suffix and not `Content-Type`, because institutional repositories serve
   PDFs as `application/octet-stream` and under URLs with no extension. Bytes
   that do not open with it are refused rather than guessed at.

2. **A manifest entry may carry `pages: [first, last]`** — physical pages in the
   file, 1-based and inclusive, so page 1 is the cover. Only those pages are
   extracted. Choosing the passage is curation, the same reviewed act as choosing
   the source, so it belongs in the committed allowlist beside the URL, and the
   digest the run manifest records covers exactly the passage that was read. The
   run manifest records the range too, so a digest names what it is a digest of.
   A range on a source that turns out not to be a PDF is refused: it means the
   curator believed something about the source that is not true.

3. **A PDF passage longer than the budget is refused, not cut.** The 6,000
   characters stop being three literals in `llm.py` and become one constant,
   `PASSAGE_CHAR_LIMIT`, in `sources.py`; the client reads documents up to it and
   `fetch_sources` refuses a PDF passage longer than it, naming the URL and the
   length, so the fix is a narrower range in the manifest rather than a silent
   loss. HTML sources are not changed by this slice — see Scope.

4. **The client pins the context length and refuses a prompt that would not
   fit.** Every request carries `num_ctx = CONTEXT_TOKENS` (16,384), so the length
   is a property of the code rather than of the machine. Before sending, a prompt
   longer than `CONTEXT_TOKENS × 2` characters is refused with `ModelRefused` —
   two characters per token is a floor Portuguese prose does not approach — so a
   manifest listing more passages than the context holds fails loudly instead of
   being truncated by the server.

**The substance manifest is recurated** onto Embrapa tier-1 extension material,
each entry with the page range of its passage, each verified on the day it was
added to return a PDF with a text layer, directly and without a redirect. **The
SciELO sources leave this cell's manifest.** They stay admissible as the
Developer decided, but as HTML they would still reach the model as their first
6,000 characters, which is exactly the input the first verdict was produced
from, and the re-probe is worth running only if it measures one change.

None of the four is hard to reverse, so none is promoted to an ADR.

## Alternatives Considered

- **Raise the character cap and send whole documents.** Rejected: a Sistema de
  Produção runs to tens of thousands of characters, which no 7-8 B local model's
  context holds with room for three of them, and a bigger cap only moves the cut
  from the front matter to the middle of the document.
- **Split each document into chunks and grade the chunks.** Rejected for this
  slice: it is retrieval inside a document, changes what a citation index points
  at, multiplies the grading calls, and puts the passage choice in a model's hands
  when the whole reason the substance layer is curated is that its source set is
  small enough to choose by hand. It becomes the right design if the passage
  choice ever has to scale past what a person can review.
- **Commit the extracted passages as text files.** Rejected for the reasons SPEC
  0071 gave for PDFs — a licence question per file, and no protection that a URL,
  a page range and a digest of what was read do not already give.
- **Decide PDF by URL suffix or `Content-Type`.** Rejected: both are set
  inconsistently by the repositories Embrapa publishes through, and a misread
  would feed binary to the HTML extractor, which returns whatever text survives
  instead of failing.
- **Refuse over-budget HTML too.** Rejected for this slice: no page range exists
  for HTML, so the refusal would make every HTML source unusable, including the
  SciELO corroboration the Developer kept admissible, before anything exists to
  select an HTML passage with. It is recorded under Risks as the cut that remains.
- **Detect truncation from `prompt_eval_count` in Ollama's reply.** Rejected: it
  can only be read after the prompt was already cut, and prompt caching lowers it,
  so it misses truncation without ever proving its absence.

## Scope

- Includes:
  - `corpus/requirements.txt` — `pypdf`, with the reason for it written beside it
    as `pyshp`'s is.
  - `corpus/src/sources.py` — `pages` on `SourceEntry` and in `SourceManifest.load`,
    PDF extraction, `PASSAGE_CHAR_LIMIT` and its refusal, `pages` on
    `FetchedSource`, and the `str | bytes` transport.
  - `corpus/src/llm.py` — `http_transport` passing a PDF through undecoded; the
    client reading `PASSAGE_CHAR_LIMIT` instead of the literal; `num_ctx`; the
    prompt ceiling.
  - `corpus/src/manifest.py` — the page range in each run-manifest source entry.
  - `corpus/sources/substance.manifest.json` — recurated as above.
  - `corpus/tests/` — a test per criterion below, with PDFs built in the test so
    the suite still needs no network and no model.
  - `corpus/README.md` and `docs/architecture/research-agent-implementation-map.md`
    — the state they record.
- Does NOT include:
  - **Running the re-probe and judging the cell.** Both are acts, not code, as
    SPEC 0071 scoped its own run; the model it runs with, `qwen2.5:7b`, is not
    pulled on this machine.
  - **Any change to HTML sources.** They are still cut at 6,000 characters, and
    no passage selector exists for them.
  - The other 43 cells, the unit overlays' search, the verification pass and the
    review gate — B2 to B4, unchanged.
  - The 300-second request timeout in `_post`. A full context on a CPU may need
    longer; the run will show it, and a timeout fails the build rather than
    hiding anything.
  - Any write to `assets/corpus/`, `lib/` or `ml/`.

## Acceptance Criteria

Each becomes a test, written before its implementation, and none needs a network
or a model.

**PDF sources**

- `a_pdf_source_is_read_as_text`: a transport returning PDF bytes yields a
  source whose text is the text on its pages.
- `a_pdf_passage_is_the_page_range_the_manifest_names`: pages outside the range
  do not reach the text.
- `a_pdf_passage_longer_than_the_budget_is_refused`: `SourceFetchError`, naming
  the URL and the length.
- `a_pdf_without_a_text_layer_fails_the_build`: a scanned document is refused
  rather than cited.
- `an_unreadable_pdf_fails_the_build`: bytes that open with `%PDF-` and do not
  parse raise `SourceFetchError` naming the URL.
- `a_page_range_beyond_the_document_is_refused`.
- `a_page_range_on_a_source_that_is_not_a_pdf_is_refused`.
- `a_body_in_bytes_that_is_not_a_pdf_is_refused`.
- `a_malformed_page_range_is_refused_at_load`: a range that is not two positive
  integers with the first no greater than the last raises `ValueError` when the
  manifest is loaded, before anything is fetched.

**The transport**

- `a_pdf_body_is_passed_through_undecoded`.
- `an_html_body_is_decoded_with_its_charset`.

**The model reads all of it**

- `a_passage_at_the_budget_reaches_the_prompt_whole`: the client's cut and the
  fetch's refusal are the same number.
- `every_request_pins_the_context_length`.
- `a_prompt_longer_than_the_context_is_refused_before_it_is_sent`: nothing
  reaches the server.

**The records**

- `the_run_manifest_records_the_page_range_its_digest_covers`.
- `the_committed_substance_manifest_loads`: it parses under the new schema and
  at least two of its sources are tier 1.

## Reproducibility

```bash
cd corpus
python -m pip install -r requirements.txt
python -m pytest tests/ -q          # no model, no network
```

Python 3.12, matching the `corpus-tests` job. `pypdf` 6.19.0. The server default
was read from `%LOCALAPPDATA%\Ollama\server.log` on Ollama 0.17.7:
`msg="vram-based default context" total_vram="0 B" default_num_ctx=4096`.

The two lengths in the Problem, re-measured with the build's own code:

```python
from src.llm import http_transport
from src.sources import extract_text
text = extract_text(http_transport(url))
len(text), text.find("INTRODU")
```

The re-probe, which this slice makes possible and does not perform:

```bash
ollama pull qwen2.5:7b
python -m src.probe --cell "Argilosa|tb_oxidic"
```

## Risks and Assumptions

- **Assumption:** two characters per token is a floor for this corpus's text.
  Portuguese prose with the Qwen tokenizer runs well above it; a passage that is
  mostly a numeric table could approach it, and the prompt would then be cut by
  the server despite passing the ceiling. The ceiling makes truncation
  unlikely, not impossible.
- **Assumption:** `pypdf` extracts a two-column page in reading order. Embrapa
  circulars are often set in two columns, and an extraction that interleaves them
  produces text a grader may reject. The run will show it, and a garbled passage
  is replaced by choosing another range or another source, not by code.
- **Risk:** the cut that remains is HTML's. Any HTML source still reaches the
  model as its first 6,000 characters. This slice removes HTML from the one cell
  it re-probes, which contains the risk and does not close it; the unit overlays
  of B3 are HTML and will meet it.
- **Risk:** a larger context is slower on a CPU, and `_post` gives a request 300
  seconds. A generation over three full passages may exceed it on this machine.
  That fails loudly and is out of scope here.
- **Risk:** `pypdf` parses untrusted binary. Only URLs the manifest lists are
  fetched, redirects are refused, and the lower bound of the pin is the current
  release rather than the first of its major version.
- **Assumption:** page numbers in the manifest are physical pages in the file,
  not the numbers printed on them. The manifest's own note says so, because the
  two differ by the cover and front matter.
- **What would invalidate this spec:** a reviewer judging the re-probed cell
  worth reading while its passages turn out to be misextracted, which would mean
  the judgement measured the model's recovery from bad input rather than the
  sources — so the run manifest's digests and the passages behind them are what
  the judgement is read against.
