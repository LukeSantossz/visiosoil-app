# SPEC: fix(research): say which clay-activity family answered when the biome default supplied it

## Problem

When the clay-activity grid resolves nothing, `CorpusComposer.compose` falls
back to `Corpus.clayActivityDefaultByBiome`, and looks up the **family-specific**
substance cell for the family that default names (#246). The result carries
that cell's tips, but its `TipsCoverage` reports `clayActivity: null` and
`substanceIsGeneric: true`.

Both fields describe the *site*, not the *composition*.
`SiteKey.substanceIsGeneric` is `clayActivity == null`, and the composer
discards `activity`, the value its lookup actually used. So:

- a reader told "generic" discounts guidance that was written for one family;
- nothing tells the reader that the family the whole substance layer is keyed
  on was guessed from biome, which the 2026-09-11 agronomic review found to be
  a lossy proxy (ADR 0022).

`test/fixtures/corpus/golden.json` pins the behaviour in its
`generic_substance_from_the_biome_default` case. No user is affected today:
`assets/corpus/corpus.json` does not ship, so the defaults are always empty in
practice.

## Design Decision

**`TipsCoverage` reports the family the substance lookup used, and whether it
was assumed.**

- **`clayActivity` becomes the family the lookup used.** That is the grid's
  family when it resolved one, otherwise the biome default's, otherwise null.
- **A new `clayActivityAssumed` flag is true when the biome default supplied
  that family**, and false when the grid resolved it or no family was used.
- **`substanceIsGeneric` becomes true only when no family was used at all**, so
  no family-specific substance cell could answer. A cell reached through the
  biome default is not generic.

The composer computes all three from `activity` and from whether
`site.clayActivity` was null. `SiteKey.substanceIsGeneric` stays as it is: it
describes the site, and the resolver tests use it that way.

**Without a corpus there is no default**, so `CorpusResearchService`'s empty
composition reports the site's family with `clayActivityAssumed: false`, which
is what it reports today.

**A result composed before this change still parses.** `clayActivityAssumed` is
optional, and its absence reads as `false`. That follows the same rule as the
other coverage fields: optional, with a documented default. A cached result from
the old biome-default path keeps saying what it said when it was composed. It
was composed with a corpus this repository has never shipped.

**The golden fixture distinguishes the two cases:**

- **`generic_substance_from_the_biome_default` becomes
  `family_specific_substance_from_the_biome_default`.** Its tips are unchanged,
  and its coverage now reads `clayActivity: "tb_oxidic"`,
  `clayActivityAssumed: true` and `substanceIsGeneric: false`.
- **A new case, `generic_substance_while_the_overlays_answer`,** has no family
  from the grid and no biome. Its land use and unit overlays answer, and its
  coverage reads `clayActivity: null`, `clayActivityAssumed: false` and
  `substanceIsGeneric: true`.

Every other case gains `clayActivityAssumed: false`, because `toJson` writes
every field.

## Alternatives Considered

- **Keep `clayActivity` as the grid's family, and add an `assumedClayActivity`
  field for the default's.** Rejected. The reader would have to combine two
  fields to learn the one fact the substance layer is keyed on. One family
  field plus a provenance flag says it directly.
- **A `clayActivitySource` enum (`grid`, `biome_default`) instead of a flag.**
  Rejected for now. Two sources exist, and a flag states them without adding a
  closed enumeration that a later corpus would need to parse defensively. If a
  third source appears, such as a user-declared family, an enum replaces the
  flag then.
- **Drop the biome default from composition.** Rejected. A defaulted answer
  beats no answer, §5.2 defines a generic response as valid, and #246 asks for
  the fallback to be visible, not removed.

## Scope

- Includes:
  - `lib/models/management_tips_result.dart`: `TipsCoverage.clayActivityAssumed`,
    its JSON round trip with an absent-means-false default, and the field docs.
  - `lib/core/services/research/corpus_composer.dart`: coverage computed from
    the lookup's family.
  - `lib/core/services/research/corpus_research_service.dart`: the empty
    composition's coverage, which writes the new flag as false.
  - `test/fixtures/corpus/golden.json`: the renamed case, the new case, and
    the new key in every case. `test/services/corpus_composer_test.dart`: the
    case list the golden must cover.
  - `test/models/management_tips_result_fields_test.dart`: the frozen
    `toJson` literal and the pre-change payload.
  - `docs/architecture/research-agent.md`: the output contract and the
    absent-field table.
  - `docs/agents/project.md`: the Known Technical Debt entry for #246 is
    removed, and `CLAUDE.md` is regenerated.
- Does NOT include:
  - Any UI. No widget reads `TipsCoverage` today.
  - The corpus build under `corpus/`, which does not compose results.
  - Re-composing cached results. The Drift cache keeps what it stored.

## Acceptance Criteria

- `golden_family_specific_substance_from_the_biome_default`: the composed
  result carries the `Argilosa|tb_oxidic` cell's tips, with coverage
  `clayActivity: "tb_oxidic"`, `clayActivityAssumed: true` and
  `substanceIsGeneric: false`.
- `golden_generic_substance_while_the_overlays_answer`: with no family from the
  grid and no biome, the overlays answer, and the coverage reads
  `clayActivity: null`, `clayActivityAssumed: false` and
  `substanceIsGeneric: true`.
- `golden_covers_every_shape_the_rule_distinguishes` lists both cases.
- `a_coverage_without_the_assumed_flag_reads_as_resolved`: a coverage JSON
  without `clayActivityAssumed` parses with the flag false, and every other
  field keeps its value.
- Every other golden case passes with `clayActivityAssumed: false`, and the
  full suite and `mf check` pass.

## Reproducibility

```sh
flutter test test/services/corpus_composer_test.dart \
  test/models/management_tips_result_fields_test.dart \
  test/services/corpus_research_service_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Risk: a reader of `clayActivity` who assumed "resolved by the grid".**
  Today that reader is only the tests and the documentation, both updated here.
  A future surface reads `clayActivityAssumed` beside it.
- **Assumption: the golden stays hand-written.** The two cases are written from
  the rule, not captured from the code, as `corpus_composer_test.dart`
  requires.
