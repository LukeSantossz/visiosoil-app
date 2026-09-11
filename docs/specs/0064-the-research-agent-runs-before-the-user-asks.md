# SPEC: docs(research-agent): supersede adr 0001 with a build-time corpus and a capped escalation

## Problem

ADR 0001's Research Agent design cannot be built as written: its named model was shut down for free and developer tiers on 2026-08-16, its ten-step per-request pipeline admits roughly four to seven requests per day against the published free daily token ceiling, and that pipeline does not complete inside the 20-second timeout the already-shipped `ProxyResearchService` applies.

## Design Decision

**The expensive pipeline moves from the request path to a build step.** ADR 0001's corrective-RAG chain is kept almost intact and run offline, once per corpus release, producing a versioned and human-reviewed JSON artifact keyed by texture class, federative unit and biome. At runtime the app performs a deterministic lookup with no model call; live per-record research survives as a third tier reached only through three fixed predicates and bounded by a spend cap that fails closed.

The move is justified by ADR 0001's own limiting statement — "**Thin inputs** (texture + location + date) cap specificity" — which is a claim about the size of the function's domain. Four classes and a bounded region set make the domain enumerable, so the per-request agent was recomputing on every capture a function with roughly a hundred distinct inputs.

Three consequences follow that no per-request variant offers: a human reviews every cell before a user reads it, runtime hallucination risk is absent rather than mitigated, and indirect prompt injection is contained at build time behind a reader instead of reaching the device. A fourth falls out of the key: because the corpus is keyed by region, the request carries region codes and the precise coordinates `ProxyResearchService` sends today stop leaving the device.

## Alternatives Considered

- **Keep ADR 0001 as written.** Rejected on arithmetic. At roughly four generations per day across all users, one agronomist sampling a morning's fields exhausts the organisation's entire daily budget, and every request would time out against the client's own 20-second limit and retry twice.
- **Keep the per-request pipeline and pay for it.** Rejected on the comparison, not on principle. The same one-time allowance buys roughly 500 runtime generations that are consumed and gone with none of them reviewed, or the whole corpus built with a frontier model with budget left for rebuilds.
- **Precompile and drop live research entirely.** Rejected. A free-text question about a specific record has an unbounded input space that no enumeration serves, and that is the one case where an agent is genuinely the right tool.
- **Materialise the full cross product of class, unit and biome.** Rejected on review cost rather than money: 208 reviewed artifacts against 51, with each agronomic correction applied once per state instead of once per biome.
- **Key by federative unit alone.** Rejected as agronomically dishonest — soil does not follow state borders, and a state spanning two biomes would average away the distinction that matters most.
- **Key by biome alone.** Rejected as losing the institutional layer; which extension service a user should consult is a state fact.
- **Route the build through a model gateway for portability.** Rejected on cost asymmetry: at build time a gateway forfeits the batch discount and the platform-enforced domain allowlist, trading roughly $25 of capability for roughly $3 of fee on a one-time budget. Portability is bought at runtime instead, where the dependency is live and the volume is small.
- **Adopt a graph orchestration framework for the build.** Rejected. The pipeline is a bounded chain run 51 times offline, and the project's own method notes list a six-plus-step RAG pipeline with no measurement as an over-engineering signal. Tracing is adopted; orchestration is not.

## Scope

- Includes:
  - `docs/adr/0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md` — new decision record.
  - `docs/adr/0001-research-agent-advisory-web-grounded.md` — marked Retired in place, keeping its number and file, with what survives and what was withdrawn stated.
  - `docs/architecture/research-agent.md` — rewritten as the design reference: current state, integration map, use case catalogue, architecture comparison, input and output contracts, source policy, `llm-wiki` strategy, security, observability, evaluation, offline behaviour, GenUI integration, delivery plan, risks, open questions, cross-terminal contracts.
  - `README.md` — the Engineering Decisions row for ADR 0001 marked Retired, and a row added for ADR 0022.
- Does NOT include:
  - Any code, in `lib/` or in a proxy repository. Every delivery slice in the architecture document passes its own Spec Gate first.
  - Any spend. The calibration probe that would replace this document's token estimates with measurements is slice 1 of that plan, not part of this change.
  - Creating the proxy repository.
  - Any change to `ml/`, the model, the preprocessing path, or the class list.
  - Any change to `lib/core/features/details/management_tips_section.dart`, which belongs to the UI/UX terminal.
  - Identifying the corpus reviewer. Six of the seven questions this design opened were decided on 2026-09-11 and are recorded in the sections they belong to; this one was not, and it blocks the corpus release rather than this change.
  - Allocating the unspent remainder of the budget, deferred by decision to the calibration probe's measurement.
  - Building the free-text input the `userQuestion` predicate needs. It is an ask to the UI/UX terminal, recorded in §18.2.
  - Bumping the `.standards` submodule.

## Acceptance Criteria

- `adr_0001_is_retired_in_place`: `docs/adr/0001-*.md` keeps its number and file, its `## Status` states the retirement date and names ADR 0022, and its body is otherwise unedited.
- `supersession_is_readable_from_both_ends`: ADR 0022 names ADR 0001 as superseded and ADR 0001 names ADR 0022 as its successor.
- `records_gate_passes`: `mf check records` reports no gap, no duplicate and no deleted record across both archives.
- `every_falsification_carries_a_dated_source`: each of the three claims that falsify ADR 0001 states what was checked and when.
- `estimates_are_labelled_as_estimates`: every token count attributed to a pipeline is marked as an estimate rather than a measurement, and the document names the slice that replaces it.
- `forbidden_fields_are_enumerated`: the input contract lists coordinates, address, imagery, EXIF and device identifiers as forbidden, and states that the proxy rejects them rather than ignoring them.
- `output_names_no_ui_component`: no field of the output contract carries a component name, per the GenUI strategy's invariant that generated content occupies slots and never selects them.
- `recommendation_divergence_is_resolved`: the design system's open coordination item is answered with the closed `category` enumeration and a stated flat fallback.
- `llm_wiki_role_is_evidence_based`: the `llm-wiki` section states the measured page counts and concludes its role from them rather than from assumption.
- `every_deferred_use_case_states_why`: each catalogue entry not in v1 carries the reason it was deferred or eliminated.
- `dormant_predicates_are_named`: the two escalation predicates that cannot fire yet name the artifact each waits on.
- `ambiguous_does_not_escalate`: the design resolves an ambiguous verdict by composing two Tier 1 cells and states that the surface renders two readings rather than one answer.
- `biome_resolves_on_device`: the biome resolver is on-device, and the document states that a server-side resolver would reinstate the coordinate egress the key removes.
- `one_time_budget_consequences_are_stated`: the document states that the rebuild cadence is funded for one year and not the second, and that Tier 2's cap fails closed permanently rather than resetting.
- `unallocated_budget_names_its_trigger`: the unallocated remainder names the measurement that decides its split and lists the candidate splits.
- `blocked_slice_is_marked_blocked`: the slice depending on the unidentified reviewer is marked blocked rather than merely unscheduled.
- `new_ux_dependencies_are_declared`: the free-text input, the durable cap-exhaustion state, the two-readings presentation and the absent-coverage statement appear as asks to the UI/UX terminal.
- `no_retry_on_not_analysed`: the design states that `notAnalysed` never escalates, per ADR 0011 and ADR 0015.
- `budget_sums_within_the_allowance`: the delivery plan's budget table sums to no more than the stated one-time allowance.
- `cross_terminal_contracts_are_two_way`: the document states what this terminal consumes from the vision terminal and what it guarantees to the UI/UX terminal, and names the shared files each owns.

## Reproducibility

This change is documentation; what needs to reproduce is the evidence behind it. Each claim was checked on the date given in the document.

| Claim | How it was checked |
|---|---|
| Model shutdown date and affected tiers | The provider's published deprecation page, fetched 2026-09-05 |
| Free-tier request and token ceilings | The provider's published rate-limit and model pages, fetched 2026-09-05 |
| Search and fetch tool pricing, batch discount | The vendor's published pricing page, fetched 2026-09-05 |
| Worker platform limits | The platform's published limits page, fetched 2026-09-05 |
| SoilGrids point API degradation | Four live `curl` probes against `rest.isric.org/soilgrids/v2.0/properties/query`, 2026-09-05: one `200` with null values at 2.8–5.6 s, three consecutive `503` |
| `llm-wiki` composition | `find wiki -name '*.md' \| wc -l` (507) and `grep -h '^area:' wiki/*.md \| sort \| uniq -c` (424 `machine-learning`), plus a case-insensitive grep for soil, agronomy and Embrapa terms returning nine UAV pages, 2026-09-05 |
| Cited `llm-wiki` pages exist | Presence check of all 25 filenames cited by the previous architecture document, 2026-09-05 |
| App-side implementation state | Read of the seven files and seven test files listed in §1.1 |
| Client timeout and retry policy | `lib/core/services/research/proxy_research_service.dart` — `_defaultTimeout` 20 s, `_defaultMaxAttempts` 3 |
| Coordinates leave the device | `proxy_research_service.dart` `fetchTips` request body includes `record.latitude` and `record.longitude` |
| Cache has no staleness check | `grep -rn retrievedAt lib/` — persisted and displayed, never compared |

Gate command: `mf check`, run from the repository root. Toolchain as pinned in `.github/workflows/ci.yml`.

## Risks and Assumptions

- **Assumption:** the four-class list is stable for the life of a corpus release. If a future ADR changes it, cells for changed classes are orphaned; the artifact carries a class-list version and keys derive from `SoilTextureLabels.ordered` so the breakage is loud rather than silent.
- **Assumption:** the token estimates are within a factor of two of reality. Slice 1 measures one cell before slice 2 spends, and the plan is re-costed if they diverge further.
- **Assumption:** a qualified human reviewer can be found for the corpus. As of 2026-09-11 none is identified, so this is a **blocker on the release slice** rather than an assumption in good standing. The design has no fallback if it proves false: the build slices proceed and no corpus ships.
- **Assumption:** guidance keyed by class, unit and biome is specific enough to be useful. The feedback loop in the observability section is what would falsify it.
- **Assumption:** the 0.1° biome grid is accurate enough. Its error is confined to transition bands; a wrong biome yields guidance for the neighbouring biome rather than a failure, which is a quieter wrong answer than a crash and therefore worth watching in the feedback loop.
- **Risk:** the twice-yearly rebuild cadence outlives its funding. At roughly $28 a year against a reserve of at most $29 that Tier 2 also draws from, year one is funded and year two is not. Recorded in the architecture document rather than mitigated, because the mitigation is recurring budget and that is not this document's to grant.
- **Risk:** Tier 2 ships enabled before the input it needs exists. Until the UI/UX terminal builds the free-text field, it serves only `corpusMiss` — a reduced feature rather than a broken one — and its one-time runway is spent on the narrowest of its three predicates.
- **Risk:** the ML terminal's D6 outcome changes the class list before the corpus is built. Mitigated by building after that decision lands, and by the class-list version.
- **Risk:** the proxy repository is never created, leaving this design unbuilt. The app then degrades exactly as it does today, through `UnavailableResearchService`, so nothing regresses.
- **What would invalidate this spec:** the app gaining crop, season or soil-chemistry inputs. The domain would stop being enumerable and the per-request architecture ADR 0001 chose would become correct again — which is why that record is retired rather than deleted.
