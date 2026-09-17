# Corpus assets

What the app composes management tips from, bundled with the binary.

| File | What it is |
|---|---|
| `corpus.json` | One reviewed corpus release: the substance, land-use and institutional layers, plus the biome-to-clay-activity defaults |
| `clay-activity-grid.bin` | The packed 0.1° grid that keys the substance layer |
| `biome-grid.bin` | The packed 0.1° grid that selects the Embrapa unit |

**All three are build products and none is tracked**, the same treatment
`assets/models/` gives the `.tflite` artifact. They are produced by the corpus
build (`docs/architecture/research-agent-implementation-map.md`, Lane B) and are
git-ignored until a reviewed release exists and a decision equivalent to ADR 0012
is taken for them.

**The app works without them.** A missing corpus means the composition answers
that there is no coverage; a missing grid leaves its key part null and the
substance layer answers generically. What is *not* tolerated is a file that is
present and malformed: that throws with the asset named, because a corrupt build
shipping as "no coverage" is a failure nobody would learn about.

Total size ceiling for this directory is **500 KB**, enforced by
`test/services/asset_corpus_store_test.dart`. Exceeding it is a decision a spec
states, not an accident.

The format of the `.bin` files is documented on `PackedGrid` in
`lib/core/services/region/grid_site_resolver.dart`, and the fixture grids under
`test/fixtures/corpus/grids/` are the contract the build must emit.
