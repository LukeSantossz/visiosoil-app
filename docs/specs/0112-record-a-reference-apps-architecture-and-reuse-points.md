# SPEC: docs(reverse-engineering): record a reference app's architecture and what VisioSoil can reuse

## Problem

VisioSoil has no written study of a shipping soil-identification app, so roadmap discussions about features such as an AI chat, a crop catalogue, a calculator, a paywall or out-of-distribution refusal argue from guesses instead of from an observed reference.

## Scope

- Includes:
  - `docs/reverse-engineering/`: a reconstruction of the Play Store app `com.indiemobileapps.soilidentifier` (v1.2): feature inventory, navigation, architecture, modules, domain model, data, network, state, identity, background work, integrations, business rules, feature deep dives, sequence diagrams and inferred ADRs. Every conclusion carries a confidence label (CONFIRMED, HIGHLY LIKELY, INFERRED, UNKNOWN) and names its evidence source.
  - `16-comparison-with-target-project.md`: each observed element classified adopt / adapt / study / discard against VisioSoil's binding ADRs.
  - `17-derived-backlog.md`: backlog *candidates* only, each naming the issue, ADR or spec it would need first.
  - `18-open-questions.md`: what the evidence could not settle, and how it could be settled legitimately.
- Does NOT include:
  - Any change to `lib/`, `ml/`, `corpus/`, `test/`, assets or the database schema.
  - Approval of any backlog candidate: each one needs its own issue, and a spec or ADR where noted, before work starts.
  - Proprietary code from the reference app, decompiled or otherwise, or any prompt text, credential, token, key, or personal account data.
  - Statements about how the reference app handles its credentials or any other security weakness of it.
  - Bypassing any protection of the reference app (licence check, billing, data sandbox, certificate trust).

## Acceptance Criteria

- `every_file_in_the_overview_document_map_exists`: each relative link in `docs/reverse-engineering/00-overview.md`'s document map resolves to a file or folder in the tree.
- `no_credential_shaped_string_is_present`: `grep -rnE "AIza[0-9A-Za-z_-]{20,}|goog_[0-9A-Za-z]{10,}|phc_[0-9A-Za-z]{10,}|@gmail\.com" docs/reverse-engineering` returns nothing.
- `no_third_party_credential_handling_is_asserted`: `grep -rniE "api.?key is|getGeminiApiKey|gemini_api_key" docs/reverse-engineering` returns nothing.
- `comparison_cites_only_existing_adrs`: every `ADR NNNN` cited in `16-comparison-with-target-project.md` and `17-derived-backlog.md` has a file under `docs/adr/`.
- `every_backlog_candidate_names_its_gate`: every row of `17-derived-backlog.md` has a non-empty Gate column.
- `standards_gates_pass`: `mf check` reports no failure on the branch.
