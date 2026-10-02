# 16 — Comparison with VisioSoil

VisioSoil's binding decisions are in `docs/adr/` and summarised in `CLAUDE.md`:
on-device descriptor classification over a released contract (ADR 0024), a
refused photo when no A4 sheet is readable and never a guessed scale (ADR 0017),
named failure causes (ADR 0015), management tips composed offline from a
reviewed corpus with no model at run time (ADR 0022, ADR 0023), Drift with
versioned migrations, and a sync outbox (not wired yet). Nothing below overrides
those decisions. Candidates that would touch them are marked **ADR needed**.

Legend: **Adopt** (take the pattern as is) · **Adapt** (take the idea, change
the shape) · **Study** (worth a spike or a spec discussion) · **Discard**
(conflicts with our decisions or is an anti-pattern).

| # | Element in Soil Identifier | Problem it solves | Their approach | Our corresponding architecture | Verdict |
|---|---|---|---|---|---|
| C1 | Gemini vision as classifier | identify soil from a photo | cloud LLM, prompt → JSON | descriptor path in an isolate over `spec.json` (ADR 0024) | **Discard**: non-deterministic, needs the network, no OOD guard |
| C2 | Defaults when the model is silent | never crash on partial output | fill 50 / pH 7 / Medium | `ClassificationReport` with ADR 0015's named causes; refusal by name (ADR 0017) | **Discard**: this is the failure our design exists to prevent |
| C3 | Non-soil photo still saved and charged | — | no OOD branch | the A4 sheet reader already refuses a photo with no readable sheet (`sheetNotFound`, ADR 0017), which stops most non-soil photos; `rejectedOod` exists with no producer (Known Technical Debt) | **Study**, narrowly: the remaining gap is a non-soil subject photographed *on* a valid sheet. Whether that is worth a producer for `rejectedOod` is an ADR question, and the closed 105-sample archive has no non-soil negatives to validate a threshold against |
| C4 | Auto-save every result | fewer taps | always persist | the preview then save flow (capture preview, SPEC 0105) | **Discard**: keep the explicit save; it prevents junk records |
| C5 | Crop step (uCrop) after capture | frame the subject | manual crop | A4 sheet rectification and patch measurement (SPEC 0091/0092) | **Discard** for classification (it would break the sheet geometry); **Study** only as a thumbnail crop for display |
| C6 | Pre-permission rationale screens | grant rate, clear denied state | in-app explainer before the system dialog | `location_rationale.dart` (before the request) and `camera_permission_denied_view.dart` (after a denial) exist; a camera explainer *before* the first request was not found | **Adopt** a camera pre-request explainer, mirroring the location one |
| C7 | Collection home with stats and search | engagement, overview | stats row + search + grid | history and home with `HomeStats`, history filter/search providers | **Adapt**: our stats already exist; consider "this month" and favourites only with a real user need |
| C8 | Favourites | prioritise records | flag on the record | — (no favourite field in schema v7) | **Study**: a new column means a schema migration and a spec |
| C9 | Per-record AI chat | follow-up questions | Gemini chat with persisted history | offline tips from the reviewed corpus (ADR 0022/0023); `ProxyResearchService` has no caller | **Discard** now (no model at run time); **Study** later via a proxy, with consent (C12) |
| C10 | Crop catalogue + compatibility score | "what can I grow here" | static list, set-membership score | management tips by `SiteKey` × texture | **Study**: crop suitability by texture class from reviewed agronomic sources could enter the corpus, never as unreviewed content (their tomato yield error shows why) |
| C11 | Soil volume calculator | how much soil to buy | L×W×D, π R² D, bags, USD | — | **Study**: low-cost pure-Dart utility; would need to be metric-first, pt-BR, no 2.5 m floor and no USD; fits agronomists only if it covers field use (e.g. limestone/gypsum dose, not bag counts) |
| C12 | AI consent modal before first AI use | disclose third-party processing | modal during onboarding | no third-party AI today | **Adopt** the pattern **if** any network AI is ever added (proxy research); not needed now |
| C13 | Remote Config for models and limits | change behaviour without a release | Firebase RC | corpus release fetch (`ProxyResearchService`), no remote config | **Study** for corpus/spec version pinning; **Discard** for credentials: never ship them through config |
| C14 | Model fallback chain | resilience to 429/503 | try primary, then backup | — | **Study** for the future research proxy (server-side, not on the client) |
| C15 | Zustand + AsyncStorage blobs | persistence | whole-store JSON | Drift + SQLite with versioned migrations and tombstones | **Discard**: ours is stronger (queries, migrations, sync metadata) |
| C16 | Client-side data migration (`migrateSoilData`) | evolve the stored shape | persist `migrate` hook | `AppDatabase.migration` cumulative steps | Already covered |
| C17 | Device-local identity, no account | zero friction | anonymous IDs | Google sign-in behind `AuthService`; sync planned | Keep ours |
| C18 | Fake "personalizing" progress | pacing before the paywall | timer animation | named processing phases are a roadmap item | **Discard** fake progress; **Adopt** honest phase labels (decode → sheet → patch → score) |
| C19 | Soft paywall, weekly trial preselected, 1 free scan | monetisation | RevenueCat | no monetisation in scope | **Discard** the dark patterns; **Study** RevenueCat only if monetisation enters the roadmap |
| C20 | Two analytics stacks, ad ID on by default | funnel analytics | Firebase + PostHog | no analytics; a local error report is in progress (#287) | **Discard** ad-ID defaults; **Study** privacy-preserving, opt-in usage telemetry separately |
| C21 | Retailer links | monetisation | Amazon / Home Depot / Lowe's | — | **Discard** |
| C22 | Template leftovers (valuation, age, materials) | — | reskinned generic model | domain-specific `SoilRecord` | **Discard**; a reminder to keep the model domain-pure |
| C23 | Static catalogues bundled in code | offline content | JS constants | corpus artefact built by `corpus/` with review | Ours is stronger (reviewed, versioned, `corpus_version` staleness) |
| C24 | Offline behaviour at quota zero | — | silent bounce to home | — | **Discard**; a reminder that every offline path needs a named, visible state |

## Patterns worth extracting (not implementations)

1. **Pre-permission rationale** (C6) is a small UX gain we may already have.
2. **Honest progress phases** (C18, inverted): their fake progress shows the gap our named phases would close.
3. **Refuse rather than fabricate** (C2, C3): the clearest lesson, and one VisioSoil already applies through ADR 0015 and ADR 0017. Their app shows the cost of the alternative: a confident-looking "Unknown, health 50/100" record that spent the user's only scan. The residual question is the narrow OOD gap in C3.
4. **Consent before third-party AI** (C12): the right template if the research proxy ever ships.
5. **Server-side model fallback** (C14): the right place for retries is the proxy, never the client, which should hold no provider credential.
