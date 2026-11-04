# Corpus assets

What the app composes management tips from, bundled with the binary from
`assets/corpus/`. This document lived in that folder until SPEC 0101 moved it
here, because a declared asset folder ships everything in it.

| File | What it is |
|---|---|
| `corpus.json` | The released corpus: the substance layer, plus the biome-to-clay-activity defaults. The format also has land-use and institutional layers, and release `2026.10.31.1` carries neither |
| `clay-activity-grid.bin` | The packed 0.1° grid that keys the substance layer |
| `biome-grid.bin` | The packed 0.1° grid that selects the Embrapa unit |

**All three are build products, and all three are tracked since SPEC 0227**,
the way `assets/models/spec.json` is. They are produced by the corpus build
([`research-agent-implementation-map.md`](../../plans/research-agent-implementation-map.md),
Lane B). Release `2026.10.31.1` was published without human review, by the
Developer's decision of 2026-10-28, so it says `humanReview: false` and every
cell carries the advisory disclaimer.

**The app works without them.** A missing corpus means the composition answers
that there is no coverage; a missing grid leaves its key part null and the
substance layer answers generically. What is *not* tolerated is a file that is
present and malformed: that throws with the asset named, because a corrupt build
shipping as "no coverage" is a failure nobody would learn about.

Total size ceiling for `assets/corpus/` is **500 KB**, enforced by
`test/services/asset_corpus_store_test.dart`. Exceeding it is a decision a spec
states, not an accident.

The format of the `.bin` files is documented on `PackedGrid` in
`lib/core/services/region/grid_site_resolver.dart`, and the fixture grids under
`test/fixtures/corpus/grids/` are the contract the build must emit.
