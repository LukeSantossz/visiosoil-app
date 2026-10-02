# 17 — Derived backlog for VisioSoil

Candidates only. Each needs its own issue, and a spec per
`.standards/docs/standards/spec_method.md` before any code. None is approved by
this document. IDs are labels, not a ranking. The cheapest wins with clear value
are B3 (camera explainer), B2 (honest phases) and B5 (visible offline states).
B1, B6 and B9 each need an ADR before anything else.

| ID | Candidate | Why (from the analysis) | Touches | Size guess | Gate |
|---|---|---|---|---|---|
| B1 | Decide whether `rejectedOod` gets a producer for the remaining gap: a non-soil subject on a valid A4 sheet (photos without a readable sheet are already refused under ADR 0017) | C3, BR-03/17: their app charges a scan for "Unknown" | inference path (existing `rejectedOod` cause), preview chip copy | M | ADR first; a threshold could be fitted one-class on the closed 105-sample archive, but nothing in it can validate the rejection side |
| B2 | Named processing phases in the capture preview (decode → sheet → patch → score) instead of a spinner | C18: their progress is fake; ours can be honest | capture preview, `InferenceService` progress events from the isolate | M | spec (already a UI/UX roadmap item) |
| B3 | Camera pre-request rationale, mirroring `location_rationale.dart` (only the post-denial view exists today) | C6, BR-13 | capture feature, `PermissionService` | S | spec |
| B4 | Favourite flag on records + filter in history | C8 | next Drift schema version, mapper, history filter provider | M | spec + migration test |
| B5 | Visible offline states for every network-dependent path (corpus refresh, future proxy, auth) | C24, BR-05 | connectivity service, affected screens | S–M | spec per surface |
| B6 | Crop suitability by texture class, as reviewed corpus content | C10 | `corpus/` build, `CorpusComposer`, golden cases | L | ADR (content scope) + spec; agronomic review mandatory |
| B7 | Field-dose calculator (e.g. liming or gypsum by area and depth), metric-first | C11 | new feature module, pure Dart | M | product decision first: is this in VisioSoil's scope? A dose depends on lab chemistry (base saturation, CEC) that a texture photo does not give, so the user would type lab values in |
| B8 | Consent screen template for any future third-party processing | C12 | onboarding, settings | S | only when a network AI feature is specified |
| B9 | Research proxy design note: server-side model fallback, key never on device | C13/C14 | `ProxyResearchService`, future backend | M | ADR (would refine ADR 0022/0023) |
| B10 | Content QA check for numeric claims in tips (ranges, units) | crop-planning content errors | `corpus/tests` | S | spec |

## Explicitly not in the backlog

Cloud LLM classification (C1), default-filled results (C2), auto-save (C4),
dark-pattern paywall (C19), ad-ID analytics (C20) and retailer links (C21).
Each conflicts with a binding decision or with the product's trust model.
