# SPEC: feat(research): load the bundled corpus and its grids from assets

## Problem

`corpusStoreProvider` binds `AbsentCorpusStore` and `siteResolverProvider` builds
a resolver with no grids, so the app can never hold a corpus or resolve a clay
activity no matter what Lane B produces — the composition path works and has no
way to be given anything to compose from.

## Design Decision

**Load the corpus and both grids from `assets/corpus/`, and distinguish a missing
asset from a malformed one.** `AssetCorpusStore` reads
`assets/corpus/corpus.json` once and caches the parsed `Corpus` for the process;
`siteResolverProvider` builds `GridSiteResolver` from the two `.bin` assets when
they are present.

**A missing asset is a normal state; a malformed one is loud.** Until Lane B
ships content, `assets/corpus/` holds no corpus, and the app must answer that
there is no coverage rather than crash — that is the state SPEC 0068 already
defines. But an asset that *is* present and does not parse is a build defect, and
swallowing it would ship guidance-shaped silence: the store rethrows with the
asset named. The two cases are told apart by whether the bundle has the key at
all, not by catching every exception the same way.

**`fetchedAt` for a bundled corpus is the corpus's own `builtAt`.** The composer
reports it as `retrievedAt`, and for a snapshot that shipped with the binary the
honest answer is when it was built, not when the app started. A served release
will supply its own fetch time when Lane C exists.

**Loading is asynchronous and happens once.** The providers expose the store and
the resolver as futures resolved at first use and cached for the process. This
runs on the main isolate, so the `rootBundle` restriction that shapes
`InferenceService` does not apply.

## Alternatives Considered

- **Ship the fixture corpus as the bundled asset so the app answers now.**
  Rejected again, for the reason SPEC 0068 gave: the fixture is synthetic and
  marked `[EXEMPLO]`, and shipping it would put example text where a user expects
  guidance.
- **Catch every load error and return null.** Rejected: it makes a corrupt asset
  indistinguishable from an absent one, so a broken build ships as "no coverage"
  and nobody learns. Missing is checked explicitly; anything else propagates.
- **Load eagerly at app start.** Rejected: it puts a file read and a JSON parse on
  the launch path for a feature most sessions never open. First use is when the
  cost is owed.
- **Keep `AbsentCorpusStore` and have the loader wrap it.** Rejected as a layer
  with no work to do. `AbsentCorpusStore` stays as the explicit empty binding for
  tests and remains what the app effectively behaves as until content ships.
- **Put the grids in the corpus JSON as base64.** Rejected: it inflates the JSON
  by a third, forces a decode on every load, and gives up the property that makes
  the format worth having — a lookup is an array index into bytes already in
  memory.
- **Include corpus fetch and version comparison here.** Rejected: fetch needs the
  release endpoint, which is Lane C and does not exist. Bundling is independently
  useful and independently testable, and splitting keeps this slice unblocked.

## Scope

- Includes:
  - `pubspec.yaml` — `assets/corpus/` declared alongside `assets/models/`.
  - `assets/corpus/.gitkeep` and `assets/corpus/README.md` — the directory and
    what belongs in it; the `.tflite`/`spec.json` precedent in `assets/models/`
    is the model for this.
  - `.gitignore` — the corpus artifacts are ignored until a reviewed release
    exists, mirroring how `assets/models/*.tflite` is handled.
  - `lib/core/services/research/asset_corpus_store.dart` — the bundle-backed
    `CorpusStore`.
  - `lib/core/services/region/` — asset loading for the two grids, as a function
    beside the resolver rather than inside it, so the resolver stays pure of I/O.
  - `lib/providers/corpus_store_provider.dart`,
    `lib/providers/site_resolver_provider.dart` — rebound to the asset-backed
    implementations.
  - Tests for every unit above, driven through an injected bundle rather than the
    real one.
- Does NOT include:
  - Corpus **fetch**, version comparison against a served release, background
    refresh, or the connectivity gate's return. All of those need the release
    endpoint, which is Lane C. This slice is the bundled half only.
  - Any real corpus or real grid content. Lane B produces those.
  - Acting on the staleness SPEC 0069 reports.
  - `lib/core/features/details/management_tips_section.dart`.
  - Any change to `ml/`, the model, the preprocessing path, or the class list.

## Acceptance Criteria

Each becomes a test, written before its implementation.

- `an_absent_corpus_asset_loads_as_no_corpus`: a bundle without the key yields
  null, and the app answers no coverage rather than throwing.
- `a_present_corpus_asset_is_parsed`: a bundle carrying the fixture corpus yields
  a `Corpus` with its version and its cells.
- `a_malformed_corpus_asset_is_loud`: a bundle whose corpus is not valid JSON, or
  whose JSON violates the corpus contract, throws rather than reading as absent,
  and the failure names the asset.
- `the_corpus_is_parsed_once_per_process`: two reads hit the bundle once.
- `fetched_at_is_the_corpus_built_at`: the composed `retrievedAt` is the
  artifact's build time, not the load time.
- `a_corpus_without_a_built_at_is_refused`: a bundled artifact with no build time
  has no honest `retrievedAt`, so it is a build defect rather than a default.
- `absent_grids_leave_their_key_parts_null`: a bundle without the grids yields a
  resolver that still resolves the federative unit from the address.
- `present_grids_resolve_their_key_parts`: a bundle carrying the fixture grids
  resolves clay activity and biome.
- `a_malformed_grid_is_loud`: a present grid that fails the format check throws
  with the asset named, rather than silently resolving to null.
- `the_assets_stay_under_the_ceiling`: whatever `assets/corpus/` holds is at most
  500 KB in total; the test states the number it measured so exceeding it is a
  decision rather than a surprise.
- `the_corpus_directory_is_declared_in_pubspec`: the asset path is registered, or
  every load would fail at runtime while every test passed.

## Reproducibility

```bash
git submodule update --init
flutter pub get
flutter test
flutter analyze
mf check
```

Toolchain as pinned in `.github/workflows/ci.yml`. Every asset test drives an
injected bundle built from `test/fixtures/corpus/`, so no test depends on the
real `assets/corpus/` being populated — which it is not, and will not be until
Lane B ships.

## Risks and Assumptions

- **Assumption:** the real corpus and grids fit the 500 KB ceiling. §19.4
  estimates roughly 460 KB, which is inside it but not comfortably, and the
  second grid arrived with the 2026-09-11 re-key. The test measures rather than
  assumes, so the first release that exceeds it fails here instead of on a
  device.
- **Assumption:** `rootBundle` is the right seam. It is what the app already uses
  for model assets, and the injected-bundle shape mirrors `InferenceService`'s
  injected `ModelAssetLoader`.
- **Risk:** the app ships with the loading path live and nothing to load, so
  every user sees "no coverage" until Lane B delivers. That is already true today
  and is not made worse; what changes is that the day content arrives, it is
  picked up without an app change.
- **Risk:** a grid whose lattice does not cover a user's coordinate resolves to
  null and the substance layer answers generically. §5.2 accepts that; the
  failure mode is quieter guidance rather than a crash, and it belongs in the
  feedback loop.
- **What would invalidate this spec:** a decision to fetch the corpus before
  first use rather than bundle it. The bundled snapshot would become an empty
  fallback and the loading order would invert.
