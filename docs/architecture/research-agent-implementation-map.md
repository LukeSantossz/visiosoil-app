# Research Agent Implementation Map

The ordered backlog for the Research Agent workstream. Every item is scoped, names
the files it touches and the tests that gate it, so executing it is implementation
rather than design. The reasoning lives in
[`research-agent.md`](research-agent.md); the decisions live in
[ADR 0022](../adr/0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md)
and
[ADR 0023](../adr/0023-the-corpus-is-built-by-local-open-source-models-and-tier-2-leaves-v1.md).
This file is the plan, and only the plan.

Last updated: 2026-09-17. **A1 and A2 are done** (SPEC 0068): the composition
path is wired end to end on the device and `researchServiceProvider` no longer
returns `UnavailableResearchService`. **It has no corpus to compose from yet** —
`corpusStoreProvider` binds `AbsentCorpusStore`, so every key answers
`insufficient_evidence` and the surface reads that as absent coverage. Content
arrives with A4, from Lane B.

## 1. What exists today

Read from the files rather than remembered. The state below is after A1 and A2
landed; everything is covered by tests.

| File | What it does | State |
|---|---|---|
| `research_service.dart` | The seam: `fetchTips(record, {locale, site, landUse})`, `ResearchResult`, `ResearchFailureKind` | Complete for v1 |
| `corpus_composer.dart` | `Corpus`, `CorpusCell` and the pure composition rule of §6.5 | Complete; pinned by `golden.json` |
| `corpus_research_service.dart` | The Tier 1 binding: composes from the held corpus, no request at all | Complete |
| `corpus_store.dart` | `CorpusStore` seam plus `AbsentCorpusStore`, the v1 binding | Loading and version comparison are A4's |
| `region/site_resolver.dart`, `region/grid_site_resolver.dart` | `SiteResolver`, `PackedGrid` and the 27-unit address table | Complete; **both grids are optional and neither ships yet** |
| `models/site_key.dart`, `models/land_use.dart` | `SiteKey`, `ClayActivity`, `Biome`, `LandUse` | Complete |
| `models/management_tips_result.dart` | The result with all nine added fields and three statuses | Complete |
| `management_tips_controller.dart` | Validate, resolve the site, call the service, persist. **No connectivity gate** | Complete for v1 |
| `providers/research_service_provider.dart` | Binds the seam to `CorpusResearchService` | Complete |
| `providers/corpus_store_provider.dart`, `providers/site_resolver_provider.dart` | The two new bindings | Rebound by A4 |
| `proxy_research_service.dart`, `http_transport.dart` | HTTP transport: 20 s timeout, 3 attempts, typed failures | Complete; **no caller until A4** |
| `unavailable_research_service.dart` | The old safe default | **Now unused** — kept until A4 proves the corpus path in the field |
| `management_tips_table.dart` and its repository | Read-through cache: `record_uuid`, `payload_json`, `retrieved_at` | Gains one column in A3 |
| `features/details/management_tips_section.dart` | The result surface | **Owned by the UI/UX terminal** — not this workstream's to edit |
| `test/fixtures/corpus/` | `corpus.json`, `golden.json`, two `.bin` grids | Synthetic content, real shape |

What does **not** exist: any real corpus, any real grid, `assets/corpus/`,
`corpus/`, and the proxy.

Schema version is **4**; A3 takes it to 5.

## 2. How to read this map

Order is a dependency order, not a priority order. An item is **ready** when
every item it names is done; **blocked** when it waits on something outside this
workstream's control. A blocked item is marked blocked rather than placed later,
so nothing silently waits.

Each slice passes its own Spec Gate before its code is written, per
`.standards/docs/standards/spec_method.md`. Tests come before implementation.

## 3. Lane A — the app answers from a corpus

No proxy, no model, no network, no spend. This lane is what turns
`UnavailableResearchService` into a feature that answers.

### A1 — slice 9a: the result carries what composition produces

**Done, SPEC 0068.** Files: `lib/models/management_tips_result.dart`,
`test/models/management_tips_result_test.dart`.

Adds the nine fields of §7 with the defaults §19.1 fixes: `category` and
`evidenceStrength` on a tip, `accessedAt` and `tier` on a source, and
`corpusVersion`, `limitations`, `alerts`, `followUpQuestions` and `coverage` on
the result. Adds `insufficient_evidence` to `ManagementTipsStatus`. Every added
field is optional in `fromJson`; closed enumerations degrade to the absent case
instead of throwing.

**This comes before slice 6, and §19.6's slice map has it after.** The composer
of slice 6 returns a `ManagementTipsResult` carrying `coverage`, and derives
`status` including `insufficient_evidence` — neither exists on the type today, so
slice 6 cannot compile against it. The order is corrected here rather than in
§19.6, which records the decision as taken on 2026-09-11 and is not rewritten
after the fact.

Gate: a payload written by today's `toJson` parses through the new `fromJson`
with the documented defaults; an unknown `category` string does not throw.

### A2 — slice 6: the site key and the composition rule

**Done, SPEC 0068**, with two deviations from the plan below, both recorded in
that spec's commits rather than discovered later:

- `ProxyResearchService` and `UnavailableResearchService` were touched after all.
  `ResearchService.fetchTips` gained two named parameters, so every implementer
  had to follow; the change is a signature and a comment in each, and no
  behaviour moved.
- The grids are **optional** on `GridSiteResolver`. They are a build product that
  arrives with A4, and the federative unit resolves from the address without
  them, so the resolver ships useful rather than waiting.

New files:

| File | Contents |
|---|---|
| `lib/models/site_key.dart` | `SiteKey(country, clayActivity, unit, biome)`, all but `country` nullable |
| `lib/models/land_use.dart` | The five-value enum of §5.3 |
| `lib/core/services/region/site_resolver.dart` | `abstract SiteResolver` |
| `lib/core/services/region/grid_site_resolver.dart` | The packed-grid implementation of §5.2 |
| `lib/core/services/research/corpus_composer.dart` | The pure function of §6.5 |
| `lib/core/services/research/corpus_research_service.dart` | The Tier 1 binding of the seam |
| `lib/core/services/research/corpus_store.dart` | Holds the corpus; version comparison |
| `test/fixtures/corpus/corpus.json` | The fixture corpus, all three layers |
| `test/fixtures/corpus/grids/` | Cropped grids covering the fixture's keys |
| `test/fixtures/corpus/golden.json` | Key → expected composed result |

Changed files: `management_tips_controller.dart`, `research_service_provider.dart`,
`management_tips_controller_provider.dart`, `research_service.dart` (two named
parameters on `fetchTips`).

**The controller's connectivity gate is wrong after this slice and must move.**
It returns `ResearchFailureKind.network` when offline, which was correct while
every result came from a proxy. Tier 1 composes locally and works offline by
design, so an offline device must get its tips rather than a failure. The gate
does not simply disappear — it belongs to corpus *fetch* (slice 8), where being
offline genuinely means "cannot refresh", not "cannot answer".

The fixture corpus is **synthetic with a real shape** (Developer's decision,
2026-09-17): every cell's text is marked as an example, so it exercises
composition without being mistaken for agronomic guidance. It must cover a
substance cell that grounds, one that abstains, a land-use overlay, an
institutional overlay, and a key that matches no substance cell.

Gate: every pair in `golden.json` composes exactly, with **citation re-indexing
across two layers as its own named test**; composing performs **zero transport
calls**, asserted with a transport fake that fails the test if touched; an
unresolved coordinate yields an all-null `SiteKey` rather than a null key; the
empty composition yields `insufficient_evidence` with a non-empty disclaimer.

### A3 — slice 7: the cache records which corpus answered

**Done, SPEC 0069.** Schema v5, a nullable `corpus_version` column,
`CachedManagementTips.isStaleAgainst` reporting staleness by exact string
inequality, and the wart below closed at the reporting level — A4 is what acts
on it.

One trap is worth carrying forward: the v5 migration step is guarded by
`from >= 4 && from < 5`, not by `from < 5`, because the v4 step's `createTable`
builds the table from today's definition and a pre-v4 database therefore already
has the column. The next added column will meet the same trap.

The original entry follows.

**Was ready after A2.** It also carries a wart A2 introduced
deliberately: an absent-corpus result is cached like any other, so a device that
cached "no coverage" keeps showing it until the user refreshes, even after a
corpus ships. A3 owns the staleness comparison, which is where the fix belongs;
its `corpus_version` column is what makes the comparison possible.
 Files: `management_tips_table.dart`, `app_database.dart`
(schema 4 → 5), `drift_management_tips_repository.dart`, the generated Drift code,
and a migration test.

One nullable column, `corpus_version`, and a cumulative `if (from < 5)` migration
in the existing style. Nullable rather than defaulted: a row cached before v5 has
no known version, and a fabricated default would claim currency it does not have.

Gate: a v4 database migrates to v5 with its rows intact and `corpus_version` null;
a row cached before the change still parses.

### A4 — slice 8: the real corpus ships and refreshes

**Bundled half done, SPEC 0070.** `AssetCorpusStore` reads
`assets/corpus/corpus.json` at first use and caches it; `AssetGridSiteResolver`
reads both grids the same way. The providers are rebound, `pubspec.yaml` declares
the directory, and the artifacts are git-ignored like the `.tflite` is. **A
missing asset is a normal state and a malformed one throws with the asset
named** — a corrupt build shipping as "no coverage" is the failure nobody would
learn about.

The resolver loads lazily rather than through a `FutureProvider`, so the provider
graph stays synchronous and no `AsyncValue` reaches the result surface, which
belongs to another terminal.

**The refresh half is still blocked** on the release endpoint (Lane C), and the
controller's connectivity gate returns with it — that is where offline means
"cannot refresh". The original entry follows.

**Was ready after A3 for the bundled half; the refresh half is blocked.** Files:
`assets/corpus/` (three files), `pubspec.yaml`, a loader and its provider, and
`proxy_research_service.dart` repurposed as the corpus fetcher.

The bundled snapshot is a fallback, never the authority: a newer served version
wins. The size ceiling is 500 KB for corpus plus both grids; exceeding it is a
decision the slice's spec states, not an accident.

**Blocked on two things at once**: the real corpus, which Lane B produces, and the
release endpoint, which is the proxy's. The bundled half can ship against a real
corpus as soon as Lane B has one; the refresh half cannot ship before the proxy
exists.

### A5 — slice 9b: rendering

**Blocked — not this workstream's.** `management_tips_section.dart` belongs to
the UI/UX terminal. What this workstream owes it is recorded in §18.2 of the
design reference, and two items changed on 2026-09-17.

With Tier 2 out of v1, the durable cap-exhaustion state is **withdrawn** as an
ask, and the absent-coverage statement becomes the only new state the surface
must carry.

And A2 falsified an assumption that surface still holds: **it disables the
refresh button when the device is offline** (`onPressed: online ? … : null`) and
renders a "Sem conexão" empty state. Both were right while every result came from
a proxy. Tier 1 composes on the device, so an offline user can now be refused an
answer the app already has. The controller's own gate was removed by A2; this one
is the UI terminal's, and it is the last place where offline still means "cannot
answer" instead of "cannot refresh".

## 4. Lane B — the corpus is built

Local models, no spend, on the Developer's machine per ADR 0023. Python 3.12 in
`corpus/`, following `ml/`'s precedent.

### B1 — slice 1: the calibration probe

**Built and run, SPEC 0071. First measured verdict: the pipeline works and the
cell is not worth reading.**

Run on 2026-09-17, `qwen2.5:7b`, seed 1234, three curated SciELO sources, cell
`Argilosa|tb_oxidic`. The chain did everything it was asked: fetched, graded —
dropping one of three documents — generated with citations, passed the grounding
check on the first attempt, and wrote the cell and its run manifest to
`corpus/out/`. **No step failed.**

The cell it produced carries one tip:

> A contribuição da argila e do carbono orgânico total (COT) para a capacidade
> de troca de cátions (CTC) pode variar dependendo do método de extração
> utilizado.

True, cited, grounded, and useless to the reader this feature exists for. The
2026-09-11 agronomic review said a cell should be four-fifths **corrections of
wrong heuristics** — what the class does not mean, and what it changes about
reading a lab report. This is a methodological aside about extraction methods.

**The binding problem is source selection, not the model.** The model summarised
faithfully what it was given, and what it was given was measurement studies. That
distinction matters for what happens next: swapping in a larger model would not
fix it, and the risk §16 records — "the guidance is correct but too generic to be
worth reading" — now has evidence rather than speculation behind it.

Two defects the run exposed, both fixed:

- **The model wrote its own disclaimer** ("podem não refletir orientações
  definitivas"), which hedges about the sources instead of stating the advisory
  stance the design took. The build sets it now; the generate prompt is at
  version 2 and no longer asks for one.
- **A 30 s fetch timeout was too tight** for an institutional site, and since an
  unreachable source fails the whole build by design, a merely slow source
  stopped it. Now 60 s.

Two things the run also settled about sources, before the model was even reached:
`agencia.cnptia.embrapa.br` no longer resolves, and the Ageitec pages on
`embrapa.br` are navigation shells with no prose. **Embrapa's substantive
material is in PDF and the extractor reads HTML only** — which is why the curated
manifest is SciELO (tier 3, which §8.1 admits on its own).

**What it needs next is a decision, not code**: which sources a substance cell may
cite, given that they must carry management guidance rather than measurement
methodology, and given that the richest ones are PDFs the fetcher cannot read
without a dependency.

**Was: ready.** Builds one cell end to end with a local model and puts it in front of
an agronomist. It no longer measures price, because there is none; it measures
whether a locally built cell is worth reading, which is the open question of §17
reached from the provider side.

Gate: one cell exists, its citations all resolve, and the judgement is recorded —
including a judgement of "not worth reading", which stops the plan before the
other cells are built.

### B2 — slice 2: cells, region tables and structured sources

**Partly built, ahead of its own gate**, because two pieces of it needed no
decision and one of them guards a risk ADR 0022 named:

- `corpus/src/keys.py` enumerates the 44 artifacts — 12 substance, 5 land-use, 27
  unit — and **reads the class list from `lib/models/soil_texture_labels.dart`
  rather than repeating it**. That is ADR 0022's own requirement: a list written
  down twice lets the corpus drift away from the model it is keyed to, silently.
  A missing or unparseable declaration fails loudly instead of falling back.
- `corpus/src/clay_activity.py` maps a SiBCS great-group name to one of the three
  families, **order first and qualifier second**, with the Latossolo trap covered
  by a test.

What B2 still owes at its gate: the rasterised grids themselves, the structured
priors, and the search backend for the 27 unit overlays.

**Was: ready after B1.** Enumerates the 12 substance cells, the 5 land-use overlays and
the 27 unit overlays, and samples the structured sources. **Two of the three unverified inputs §15.3 lists were checked on 2026-09-17.**
IBGE biome boundaries exist as open-data shapefiles at 1:250 000 — better than
assumed. The national soil map is obtainable, but **Embrapa's copy is CC BY-NC,
which this product cannot use** because §15.2 records it as a field product as
well as an academic one; IBGE publishes the equivalent under the federal
open-data policy, and that is the copy to read. The third — whether map units
collapse into three clay-activity families — **is answered from the
classification system**: SiBCS's third categorical level, which is the level the
map is classified at, is itself defined with emphasis on clay activity, at the
same 27 cmolc/kg threshold. The family is constitutive of the class name rather
than inferred from it. The attribute table itself is still unopened, and the
mapping is **order first, qualifier second** — a Latossolo is low-activity by
definition and carries no "Tb" in its name, so a string search would resolve it
wrongly to unknown.

**This slice's gate decides the search backend.** See §6.

### B3 — slice 3: the build pipeline

**Ready after B2.** Query transform, allowlisted search, source grading,
generation with citations, grounding graders. The chain is CRAG-shaped: the grader
is external and light, which is what makes a small local model adequate for it.

The allowlist is **our code now**, not a provider parameter. Gate: the injection
fixture of §12.4 passes and every citation resolves.

### B4 — slice 4: verification and the human review gate

**Blocked.** The cross-family verification pass is ready after B3; the human
review gate is blocked because **no reviewer is identified**, and none of the
alternatives considered produced a fallback. Build slices proceed; no corpus is
released.

## 5. Lane C — the proxy

**Not started, and not on the critical path.** With Tier 1 composing on the device
and Tier 2 out of v1, the proxy's only v1 job is serving corpus releases with an
ETag. Lane A's A1 through A3 and all of Lane B run without it.

Deferred with it: the Tier 2 endpoint, its cap and its unreviewed-output marking.
ADR 0023 removes them from v1.

## 6. Open decisions

| Question | Candidates | What separates them | Decided at |
|---|---|---|---|
| **Search backend for the build** | A curated document set with no live search; a self-hosted meta-search engine; a free search library | Injection surface, reproducibility, and how much manual curation 44 cells over 27 states actually needs | B2's Spec Gate |
| **Generator and verifier models** | Any two Ollama-served families that fit 8 GB | Measured quality on one cell, not a guess | B1's measurement |
| **Who reviews the corpus** | None identified | — | Blocks B4; no fallback exists |

## 7. Order of execution

```
A1 ──► A2 ──► A3 ──► A4 (bundled half: DONE)
                       ▲
B1 ──► B2 ──► B3 ──► B4 (blocked: reviewer)
                       │
                       └──► the corpus A4 ships

Lane C ── not on the critical path ── A4 (refresh half), and nothing else in v1
A5 ── UI/UX terminal ── after A1 lands the fields it renders
```

A1 through A3 are the shortest path to the feature answering at all. They need no
corpus, no model, no network and no proxy: they answer from the fixture, which is
why the fixture is a repository asset rather than a throwaway.
