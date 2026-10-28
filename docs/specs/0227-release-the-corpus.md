# SPEC: feat(corpus): release the substance corpus into the app

## Problem

The app composes management tips from `assets/corpus/corpus.json` and resolves
the substance key through `assets/corpus/clay-activity-grid.bin` and
`assets/corpus/biome-grid.bin`. None of the three ships. `.gitignore` keeps
them out "until a reviewed release exists (SPEC 0068)", and nothing in
`corpus/` writes `corpus.json` at all: the probe writes one cell and its run
manifest to `corpus/out/`, and its docstring says that output never lands in
`assets/corpus/`. So every record composes to `insufficient_evidence`, and the
feature has never been seen working on a device.

What the app needs, confirmed on `main`:

- `AssetCorpusStore` reads `corpus.json`. It refuses a file with no usable
  `builtAt`, an empty `disclaimer` or no `corpusVersion`. A missing file means
  no coverage, and a malformed one throws.
- `CorpusComposer` takes the clay-activity family from the clay grid at the
  record's coordinate. When the grid has none, it falls back to
  `clayActivityDefaultByBiome[biome]`, with the biome read from the biome
  grid. Failing both, it has no substance cell.
- The substance key is `"<textureClass>|<clayActivity>"`, over the four
  classes the model emits and the three families: twelve cells.

## Design Decision

**A release command reads one build's twelve substance cells and the two grids,
checks them, and writes `corpus.json` and both grids into `assets/corpus/`. The
three files are tracked, so the APK carries them.**

- **`python -m src.release`** in `corpus/`. It takes the directory the probe
  wrote, the directory `build_grids` wrote, the corpus version, and the output
  directory (`../assets/corpus` by default).
- **The cells.** Each cell is read with its run manifest, and its key comes
  from the manifest, not from the file name. The release refuses, naming the
  cause, when:
  - a key of `keys.substance_keys()` has no cell, or a cell has a key outside
    it;
  - two manifests name different models, or different prompt versions. One
    release is one build, and a cell built under an older prompt would ship
    under a version that does not describe it;
  - a cell fails `validate_cell`, which already requires a non-empty
    disclaimer on every cell.
  An abstained cell is released as it is. The app shows it as abstained, and
  forcing it to ground is what the build refuses to do.
- **The grids** are copied byte for byte. The release refuses a file whose
  magic or kind is not the expected one, and two grids on different lattices.
- **`clayActivityDefaultByBiome` is derived from the grids**: for each biome,
  the family most of its resolved cells carry, with ties going to the earlier
  family in `keys.CLAY_ACTIVITIES`. A biome with no resolved cell gets no
  default. This replaces a table someone would have to write by hand with one
  the source maps state.
- **`corpus.json`** holds the fixture's top-level fields:
  - `corpusVersion`, `classListVersion` (`"v1-four-class"`, as
    `research-agent.md` §6.1 names it), `model`, `builtAt` (the release
    instant, UTC), the corpus `disclaimer` (the substance disclaimer), the
    biome defaults, and `substance`;
  - `humanReview: false`, so the artifact itself says no person reviewed it.
    The app ignores the field.
  It holds no `landUse`, `unit` or `biome` layer: they are out of scope today,
  and the app reads an absent layer as empty.
- **The files leave `.gitignore`.** A clone, CI's release build and the smoke
  test then all carry the same corpus, the way `assets/models/spec.json` is
  tracked (ADR 0012). The cost is about 320 KB in the repository and the APK.
  Building the grids needs the IBGE shapefiles, about 5 minutes and a
  download, which CI should not depend on.
- **Published without B4's human review.** The Developer decided on 2026-10-28
  to publish the cells without the named human review B4 calls for. They will
  be validated through the feature in use and corrected afterwards. Every cell
  carries the advisory disclaimer, and `humanReview: false` records the
  decision in the artifact. The implementation map records it beside the
  decision to go on without the agronomist's judgement.
- **The probe's docstring** changes to say its output reaches `assets/corpus/`
  only through the release.

## Alternatives Considered

- **Keep the files ignored and build them in CI.** Rejected: CI would need the
  IBGE download and a local model to reproduce the cells, and a model's output
  is not reproducible across runners.
- **Hand-write the biome defaults.** Rejected: the fixture's table is
  synthetic. A table derived from the grids is reproducible, and the
  pedological judgement stays in `clay_activity.py`, where it is tested.
- **Release only the grounded cells.** Rejected: an absent cell reads as "no
  substance cell" and the result goes generic. An abstained cell tells the
  reader the sources did not support guidance, which is the truer statement.

## Scope

- Includes:
  - `corpus/src/release.py` and its tests;
  - the three files in `assets/corpus/`, and the two `.gitignore` lines
    removed;
  - a Dart test that reads the released `corpus.json` with the app's parser,
    and composes every substance key;
  - the probe's docstring, the implementation map, and `docs/agents/project.md`
    on what ships.
- Does NOT include:
  - The land-use (5) and unit (27) layers, and a producer for
    `evidenceStrength`. They are out of scope by the Developer's decision of
    2026-10-28.
  - New sources. A cell the three Embrapa sources do not cover abstains.
  - A release endpoint or a refresh path. The bundled snapshot is the only
    corpus.

## Acceptance Criteria

- `the_release_writes_the_fixtures_fields`: the written `corpus.json` carries
  every top-level field of `test/fixtures/corpus/corpus.json` except `_note`
  and the three layers out of scope, each of the same JSON type, and each
  cell's fields are fields the fixture's cells use.
- `a_missing_or_extra_key_is_refused`.
- `cells_from_two_builds_are_refused`: a different model or prompt version.
- `an_invalid_cell_is_refused`: a citation outside its sources, and an empty
  disclaimer.
- `an_abstained_cell_is_released_as_it_is`.
- `the_grids_are_copied_byte_for_byte`, and `a_wrong_grid_is_refused` (magic,
  kind, lattice).
- `the_biome_default_is_the_most_common_family`: including the tie rule and a
  biome with no resolved cell.
- `the_release_says_no_person_reviewed_it`: `humanReview` is `false`.
- Dart, `test/services/released_corpus_test.dart`:
  - the released `corpus.json` parses through `AssetCorpusStore`;
  - it has the twelve substance keys;
  - every biome has a default;
  - composing each key gives a grounded or abstained result without throwing.
- Every existing corpus and Flutter test passes.

## Risks

- **Unreviewed guidance reaches users.** It is the Developer's decision, taken
  knowing the risk §16 records. The mitigations are the disclaimer on every
  cell, the derived limitations, abstention wherever grounding failed, and
  `humanReview: false` in the artifact.
- **A 7B model's labels and grounding can be wrong.** Each cell's run manifest
  stays in `corpus/out/` for a later review, which is git-ignored and so lives
  on the machine that ran the build.
- **The derived defaults can disagree with pedology.** The mode is only as good
  as `clay_activity.py`'s mapping and a 0.1° centre sample. It is used only
  where the clay grid itself has no value.
