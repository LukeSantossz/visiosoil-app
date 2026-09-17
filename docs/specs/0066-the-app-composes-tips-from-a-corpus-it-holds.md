# SPEC: feat(research): compose management tips on the device from a held corpus

## Problem

`researchServiceProvider` returns `UnavailableResearchService`, so the Management
Tips feature reports the proxy as unavailable on every call and no user has ever
seen a tip; the composition rule ADR 0022 specified has no implementation, and the
result type cannot carry what composition produces.

## Design Decision

**Implement the Tier 1 path end to end, on the device, and rebind the seam to it.**
The result type absorbs the nine fields of §7 and the third status member;
`SiteResolver` turns a coordinate into a `SiteKey`; `CorpusComposer` is the pure
function of §6.5; `CorpusResearchService` binds the seam to local composition; and
`CorpusStore` holds the corpus. No network call, no model, no proxy.

**An absent corpus is a normal state, not an error.** Until Lane B produces a real
corpus, `CorpusStore` holds none, composition yields `insufficient_evidence` with
an empty tips list and a non-empty disclaimer, and the surface states that there is
no coverage. That is strictly more honest than today's "the service is
unavailable", and it means the whole path is wired and exercised on a real device
from this slice forward rather than waiting for the corpus to prove it works.

This slice is what the implementation map calls A1 and A2 together. They are one
spec rather than two because A1 alone would add nine fields nobody writes and one
status nobody produces — the implemented-and-uncalled shape ADR 0023 refuses to
repeat. Together they deliver one outcome: the app composes.

## Alternatives Considered

- **Split A1 and A2 into two gates.** Rejected: A1 alone ships a widened type with
  no producer, which is the debt `ClassificationVerdict` and `ImageQualityAnalyzer`
  already represent in this repository and which ADR 0023 refused to add a third
  of. The compile-order dependency is real; a gate boundary at that seam is not.
- **Ship the fixture corpus as the bundled asset so the app answers on a device
  now.** Rejected. The fixture is synthetic and marked `[EXEMPLO]` by decision, and
  shipping it would put example text where a user expects guidance. The absent
  corpus path exists precisely so the wiring can be real while the content is not.
- **Keep `UnavailableResearchService` bound until a corpus exists.** Rejected: it
  keeps the new code uncalled, which is the thing this spec is shaped to avoid, and
  it reports a transport failure for a state that is not one.
- **Put the resolver inside `CorpusResearchService`.** Rejected per §19.3: resolving
  is orchestration, the controller already owns orchestration, and a resolver inside
  the service would make the service unfakeable without a grid asset.
- **Let `CorpusComposer` read assets and the clock.** Rejected: it is specified as a
  pure function so the golden fixture can pin it. `retrievedAt` comes from the
  corpus, not from `DateTime.now()`.
- **Merge duplicate sources during composition.** Rejected per §6.5, and restated
  here because it is the tempting simplification: merging would re-index across
  layers and add a second place an index can be wrong, to save a repeated line.
- **Make the added fields required and migrate the cache.** Rejected per §7: the
  Drift cache reads old payloads through the new parser, so a required field would
  make every cached row fail to parse and the user would silently lose offline tips.
- **Implement `GridSiteResolver` against real grids.** Not possible and not wanted
  here: the real grids are Lane B's output. It is implemented against the fixture's
  cropped grids, which is what §19.5 put them there for.

## Scope

- Includes:
  - `lib/models/management_tips_result.dart` — the nine fields of §7 with the
    defaults of §19.1, and `insufficient_evidence` added to
    `ManagementTipsStatus`.
  - `lib/models/site_key.dart`, `lib/models/land_use.dart` — new value types.
  - `lib/core/services/region/site_resolver.dart`,
    `lib/core/services/region/grid_site_resolver.dart` — the resolver seam and its
    packed-grid implementation.
  - `lib/core/services/research/corpus_composer.dart` — the pure function of §6.5.
  - `lib/core/services/research/corpus_research_service.dart` — the Tier 1 binding.
  - `lib/core/services/research/corpus_store.dart` — holds the corpus, including
    the absent case.
  - `lib/core/services/research/research_service.dart` — `fetchTips` gains
    `SiteKey site` and `LandUse? landUse` named parameters.
  - `lib/core/services/research/management_tips_controller.dart` — resolves the
    site and passes it; **the connectivity gate is removed**, because Tier 1
    composes offline by design.
  - `lib/providers/research_service_provider.dart`,
    `lib/providers/management_tips_controller_provider.dart`,
    and a provider for the resolver and the store.
  - `test/fixtures/corpus/corpus.json`, `test/fixtures/corpus/grids/`,
    `test/fixtures/corpus/golden.json` — synthetic content, real shape.
  - Tests for every unit above, plus the two silent-failure tests §19.7 names.
- Does NOT include:
  - `assets/corpus/`, `pubspec.yaml`, the corpus loader's asset path, or corpus
    fetch and version comparison. That is A4 and it has its own gate.
  - The schema v4→v5 `corpus_version` column. That is A3 and it has its own gate;
    until it lands, `corpusVersion` round-trips inside `payload_json` like every
    other field.
  - `lib/core/features/details/management_tips_section.dart` and any rendering.
    It belongs to the UI/UX terminal. No change is required of it: it routes on
    `status == abstained || tips.isEmpty`, and an `insufficient_evidence` result
    has empty tips.
  - `ProxyResearchService` and `http_transport.dart`. Untouched; they have no
    caller until A4.
  - Any Tier 2 code, per ADR 0023.
  - The real grids and the real corpus. Both are Lane B's.
  - Any change to `ml/`, the model, the preprocessing path, or the class list.

## Acceptance Criteria

Each becomes a test, written before its implementation.

**The result type**

- `absent_fields_parse_to_documented_defaults`: a payload written by the pre-change
  `toJson` parses, and each of the nine fields holds the default §19.1 states.
- `unknown_enum_member_does_not_throw`: a `category` or `evidenceStrength` string
  the build does not know degrades to null rather than throwing.
- `unknown_status_still_throws`: an unrecognised `status` is a malformed payload,
  not a degraded one, and is not silently swallowed.
- `to_json_writes_every_field`: anything this version caches round-trips complete.
- `insufficient_evidence_is_a_status`: `ManagementTipsStatus` has three members.

**The site key**

- `unresolved_coordinate_yields_all_null_site_key`: a null latitude or longitude
  returns a `SiteKey` whose fields are null, never a null key.
- `resolver_reads_both_grids`: clay activity and biome are resolved independently,
  and one resolving while the other does not is a valid key.
- `out_of_country_coordinate_resolves_to_no_unit`: a coordinate outside Brazil
  yields a key with no unit and no biome rather than a wrong one.

**The composition rule**

- `golden_fixture_composes_exactly`: every pair in `golden.json` matches.
- `citations_are_reindexed_across_layers`: its own named test, because it is the
  case most likely to be implemented wrongly.
- `duplicate_sources_are_not_merged`: the same URL in two layers appears twice
  with two indices.
- `layer_order_is_fixed`: substance, then land use, then institutional, never
  interleaved.
- `empty_composition_is_insufficient_evidence`: a key matching no substance cell
  yields `insufficient_evidence`, an empty tips list and a non-empty disclaimer,
  and never throws.
- `status_is_derived_per_the_rule`: grounded when any layer contributed, abstained
  when the substance layer abstained explicitly, insufficient otherwise.
- `limitations_are_deduplicated_by_exact_string`.
- `composer_is_pure`: composing twice with the same input yields an equal result,
  and `retrievedAt` comes from the corpus rather than from the clock.

**The wiring**

- `composition_performs_zero_transport_calls`: asserted with a transport fake that
  fails the test if touched — stronger than asserting an absent field, and it is
  the property §6.1 actually claims.
- `absent_corpus_composes_insufficient_evidence`: with no corpus held, the service
  returns `ResearchSuccess` carrying an `insufficient_evidence` result, not a
  `ResearchFailure`.
- `provider_binds_corpus_research_service`: `researchServiceProvider` no longer
  returns `UnavailableResearchService`.
- `offline_device_still_receives_tips`: the controller returns success with the
  connectivity service reporting offline, because Tier 1 does not need the network.
- `invalid_record_still_fails_fast`: a record without a uuid or without a
  classification still returns `invalidRecord`; removing the connectivity gate does
  not remove the validity gate.

## Reproducibility

```bash
git submodule update --init
flutter pub get
flutter test
flutter analyze
mf check
```

Toolchain as pinned in `.github/workflows/ci.yml`: Flutter 3.44.1 / Dart 3.12.1.
No randomness, no network, no device. The fixture corpus and `golden.json` are
committed, so every composition assertion reproduces from the repository alone.

## Risks and Assumptions

- **Assumption:** the packed-grid format can be fixed by this slice without the
  real grids existing. It can — the fixture's cropped grids are written by this
  slice and become the format Lane B must emit, which makes the fixture a contract
  rather than a convenience. If Lane B finds the format wrong, the fixture and the
  reader change together and the golden catches the mismatch.
- **Assumption:** an `insufficient_evidence` result renders acceptably today.
  Verified by reading `management_tips_section.dart`: it routes on
  `status == abstained || tips.isEmpty`, so an empty-tips result already takes the
  abstained branch. The copy will not yet say "no coverage for this region" —
  that is the UI/UX terminal's ask in §18.2, and until it lands the user sees the
  abstention copy, which is wrong in wording but not in meaning.
- **Risk:** removing the connectivity gate loses a genuine check. It does not
  disappear — it belongs to corpus *fetch*, where offline means "cannot refresh".
  A4 is where it returns, and this spec names that so it is not simply dropped.
- **Risk:** the nine fields land before any producer writes them, so their defaults
  are exercised only by tests until a corpus exists. Accepted: the alternative is
  a composer that cannot compile, and the defaults are the cache-compatibility
  contract, which is testable without a producer by construction.
- **What would invalidate this spec:** a decision to compose on the proxy instead
  of on the device. ADR 0022 rejected it for reasons this slice does not weaken,
  and the whole file list would change.
