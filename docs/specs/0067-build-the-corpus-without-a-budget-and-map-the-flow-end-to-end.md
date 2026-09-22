# SPEC: docs(research-agent): build the corpus without a budget and map the flow end to end

## Problem

ADR 0022's plan has no first slice that can run: three of its decisions — a pinned
paid provider, a platform-enforced source allowlist, and a Tier 2 bounded by a
fail-closed spend cap — all rest on a $50 allowance that was never released, and
no record covers building the corpus without one.

## Design Decision

**The corpus build runs on local open-source models served by Ollama, through the
`LLMClient` and `SearchClient` seams ADR 0001 specified and ADR 0022 kept, and
Tier 2 leaves v1.** The paid provider becomes a second implementation behind the
same seams, selected by configuration, and is what a funded rebuild uses. A key
the corpus does not cover is answered by saying there is no coverage for that
region, which §6.5 already defines as a valid composition.

The substitution is defensible for this pipeline specifically, not in general:
the build is grounded generation over documents it retrieves, so the substance
comes from the fetched sources rather than from the model's parametric memory.
That is the regime where a small model is closest to a large one —
`small-language-models.md` records RETRO at 7.5 B reaching GPT-3 at 175 B once
retrieval carries the facts, and `rag-auto-corretivo.md` records CRAG's grader as
deliberately external and light, plug-and-play rather than a capability of the
generator. The hardware is already present: an RTX 3070 with 8 GB of VRAM, 31 GB
of system memory, and Ollama installed.

Two prices are named rather than absorbed. The source allowlist moves from the
provider's `allowed_domains` parameter into our own code, where it becomes a
filter we implement and test instead of a platform guarantee. And the quality gap
against the paid path is **unmeasured** — the calibration probe ADR 0022 costed at
$1 becomes free, and its purpose changes from measuring price to measuring
whether one locally built cell is worth reading.

This change also produces the ordered implementation map the workstream has never
had, mirroring `ml-implementation-map.md`, and corrects one defect in the slice
order §19.6 records: slice 6's composer produces a `ManagementTipsResult` carrying
`coverage`, `category` and `evidenceStrength`, so slice 9's model fields must
land before slice 6 rather than after it.

## Alternatives Considered

- **Wait for the budget.** Rejected: it defers the whole feature on a contingency
  with no date, when the app half needs no model at all and the hardware for the
  build half is already on the desk.
- **Pin the local provider the way ADR 0022 pinned the paid one.** Rejected for
  the inverse of ADR 0022's own reason. Pinning bought a batch discount and a
  platform-enforced allowlist; locally there is neither, so pinning would buy
  nothing and would cost the funded rebuild a rewrite.
- **Keep the paid path as the default, local as a fallback.** Rejected as a
  record describing a build nobody can run. The default is the path that works
  today.
- **Implement both paths fully now and select at run time.** Rejected on
  maintenance rather than principle: both implementations would have to be tested
  against every cell, and the second has no user until a budget exists. The seam
  is kept and only one side is implemented; the spec that adds the other says so.
- **Ship Tier 2 disabled behind a flag.** Rejected. This repository already
  carries `ClassificationVerdict` and `ImageQualityAnalyzer` implemented, tested
  and called by nobody, each waiting on a wiring spec. A third would repeat a
  mistake that is already recorded as debt.
- **Serve Tier 2 from the Developer's own Ollama.** Rejected as a demonstration
  presented as a product: it works while one machine is on, and an agronomist in
  a field reaches nothing.
- **Answer everything live from a local model and drop the corpus.** Rejected for
  the reason ADR 0022 gave, which a local model does not weaken: an unreviewed
  model answering agronomic questions at runtime is the risk the design exists to
  remove. Running it locally removes the cost, not the risk.
- **Decide the search backend here.** Rejected as premature. It is not an input to
  any slice before slice 2, and the three candidates differ in ways that slice 2's
  own checks resolve. It is recorded as open with a stated trigger rather than
  guessed at now.
- **Write the map as a section of `research-agent.md`.** Rejected: that document
  is the design reference and states its own reasoning; the map is a backlog that
  changes as slices land. `ml-implementation-map.md` already separates the two for
  the other terminal, and the same split is what keeps the reference stable.

## Scope

- Includes:
  - `docs/adr/0023-the-corpus-is-built-by-local-open-source-models-and-tier-2-leaves-v1.md`
    — new decision record.
  - `docs/architecture/research-agent-implementation-map.md` — the ordered
    backlog: what exists, what each slice builds, in what order, with the
    dependency that §19.6 got wrong corrected.
  - `docs/architecture/research-agent.md` — §15 (delivery plan and budget), §20.3
    (model and search providers) and §20.5 (how the build runs) brought into
    agreement with ADR 0023, and the Tier 2 slices marked as out of v1.
  - `README.md` — a row added for ADR 0023 in Engineering Decisions.
- Does NOT include:
  - Any code, in `lib/`, in `corpus/`, or in a proxy repository. Every slice
    passes its own Spec Gate first.
  - Retiring or editing ADR 0022. It is narrowed, not superseded: its
    architecture stands and this record is only readable against it.
  - Choosing the search backend, the generator model or the verifier model. The
    first is slice 2's gate; the other two are the calibration probe's
    measurement.
  - Creating `corpus/` or `assets/corpus/`.
  - Any change to `ml/`, the model, the preprocessing path, or the class list.
  - Any change to `lib/core/features/details/management_tips_section.dart`, which
    belongs to the UI/UX terminal.
  - Bumping the `.standards` submodule.

## Acceptance Criteria

- `adr_0023_states_what_it_narrows`: ADR 0023 names ADR 0022, states which of its
  decisions it narrows and which consequence it reverses, and states that ADR 0022
  is not retired.
- `adr_0022_is_unedited`: `docs/adr/0022-*.md` is byte-identical to its state on
  `main` before this change.
- `records_gate_passes`: `mf check records` reports no gap, no duplicate and no
  deleted record across both archives.
- `allowlist_cost_is_stated`: the record states that `allowed_domains` enforcement
  is lost and that the allowlist becomes code with a test behind it, rather than
  presenting the substitution as free.
- `quality_gap_is_labelled_unmeasured`: the record states that no local model was
  run against a cell before it was written, and names the probe that measures it.
- `verifier_independence_is_preserved`: the record requires the verifier to be a
  different model family from the generator, and states why a different
  temperature of the same model would not be a check.
- `build_guard_is_replaced_not_dropped`: the record states that ADR 0022's
  confirmation input and spend ledger existed to protect money, and names the run
  manifest as the guard that replaces them and the question it answers instead.
- `tier_two_removal_names_the_user_visible_effect`: the record states what a user
  sees when the corpus does not cover their key, rather than only that Tier 2 is
  absent.
- `tier_two_removal_costs_no_migration`: the record states that the output
  contract is unchanged, because the fields a later Tier 2 fills are already
  optional with documented defaults.
- `orphan_transport_is_named`: the record states that `ProxyResearchService` has
  no caller until slice 8, so it is not mistaken for dead code.
- `map_lists_every_file`: the implementation map names, for each slice, the files
  it creates or changes and the tests that gate it.
- `map_corrects_the_slice_order`: the map states that slice 9's model fields
  precede slice 6, and states the dependency that forces it.
- `map_separates_blocked_from_unscheduled`: each item the map cannot schedule
  names what it waits on, and a blocked item is marked blocked rather than merely
  later.
- `map_states_what_exists_today`: the map lists the files that already exist and
  what each does, so the first slice starts from a verified baseline rather than a
  remembered one.
- `open_search_backend_names_its_trigger`: the search backend is recorded as open,
  with the three candidates, what separates them, and the gate that decides it.
- `architecture_agrees_with_the_adr`: no statement in `research-agent.md` still
  says the build is pinned to a paid provider, runs in CI under a repository
  secret, or that Tier 2 ships enabled in v1.
- `readme_row_resolves`: the README's Engineering Decisions row for ADR 0023
  links to a file that exists, and `test/standards/readme_adr_index_test.dart`
  passes.

## Reproducibility

This change is documentation; what needs to reproduce is the evidence behind it.

| Claim | How it was checked |
|---|---|
| The machine can serve a 7–8 B model | `nvidia-smi --query-gpu=name,memory.total` → `NVIDIA GeForce RTX 3070, 8192 MiB`; `Win32_ComputerSystem.TotalPhysicalMemory` → 30.9 GB, 2026-09-17 |
| Ollama is installed | `Get-Command ollama` → `C:\Users\lucas\AppData\Local\Programs\Ollama\ollama.exe`, 2026-09-17 |
| Retrieval narrows the small-model gap | `llm-wiki/wiki/small-language-models.md`, RETRO 7.5 B row, read 2026-09-17 |
| CRAG's grader is external and light | `llm-wiki/wiki/rag-auto-corretivo.md`, "As duas linhagens que este padrão mistura", read 2026-09-17 |
| Template Generation is the pattern in force | `llm-wiki/wiki/salvaguardas-llm.md` §Pattern 29, read 2026-09-17 |
| The app-side baseline the map records | Read of `lib/core/services/research/` (5 files), `lib/models/management_tips_result.dart`, `lib/providers/research_service_provider.dart`, 2026-09-17 |
| `researchServiceProvider` returns the unavailable binding | `lib/providers/research_service_provider.dart` returns `const UnavailableResearchService()` |
| Slice 6 depends on slice 9's fields | §6.5 derives `coverage` and §7 puts it on the result; `ManagementTipsResult` has no such field today |

Gate command: `mf check`, run from the repository root. Toolchain as pinned in
`.github/workflows/ci.yml`.

## Risks and Assumptions

- **Assumption:** a 7–8 B local model can grade sources and generate cited
  guidance well enough to pass the review checklist of §12.3. Unverified — the
  calibration probe is what falsifies it, and it now costs time rather than money,
  so it can be repeated with a different model at no cost.
- **Assumption:** the machine stays available for builds. A corpus rebuild twice a
  year depends on one desk. Recorded rather than mitigated; a funded rebuild moves
  off it by configuration.
- **Risk:** the allowlist, now our code, is implemented wrongly and a source
  outside the policy reaches a cell. Mitigated by making it a filter with the
  injection fixture of §12.4 behind it, and by the human review gate, which reads
  every source before release.
- **Risk:** the quality gap is large enough that the corpus is not worth
  reviewing. This is the same open question ADR 0022 recorded — whether the
  guidance is specific enough to be worth reading — reached from a second
  direction. The probe answers both at once, and answering "no" stops the plan
  before fifty cells are built.
- **Risk:** deferring Tier 2 reads as a reduced product. It is one; the design
  says so rather than hiding it, and the output contract leaves the door open at
  no migration cost.
- **Assumption:** the search backend can be decided at slice 2 without
  invalidating slices 6 through 9. It can: those slices consume a corpus file and
  never know how its sources were found.
- **What would invalidate this spec:** a released budget. The seam would then be
  configured to the paid provider and ADR 0022's original stack would apply
  unchanged, which is why that record is narrowed rather than retired.
