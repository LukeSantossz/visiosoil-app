# 15 — Inferred architectural decisions

Each ADR is inferred: it records what the codebase behaves as if had been
decided, with the evidence and the visible consequences.

## Recurring patterns

```text
OBSERVED:  every feature reads and writes global Zustand stores; no repository types exist.
INFERRED:  "stores as view models" with service modules around SDKs.
EVIDENCE:  store action names across collection, user, premium; service names per SDK (E-S).

OBSERVED:  every AI capability calls Gemini directly from the device.
INFERRED:  "no backend" is a deliberate cost and speed choice for a template app.
EVIDENCE:  no first-party API host (E-S); model reply observed (E-O).

OBSERVED:  every result field has a default.
INFERRED:  the renderer must never crash on partial model output, at the price of fabricating values.
EVIDENCE:  50/50/50, pH 7, "Medium", "Fair" on a non-soil image (E-O).
```

## ADRs

| ADR | Decision | Evidence | Consequences |
|---|---|---|---|
| ADR-01 | **React Native, New Architecture, Hermes, bare CLI** | E-N, E-D | One JS codebase, iOS-ready; Kotlin limited to the host |
| ADR-02 | **No first-party backend; vendor SDKs only** | E-S | Cheap to run; no server-side control point; no cross-device data |
| ADR-03 | **LLM vision (Gemini) as the classifier** | E-S, E-O | No model to train; non-deterministic; no OOD guard; per-call cost; network required |
| ADR-04 | **Remote Config for model names and quota** | E-S | Model or limit changes without a release; fallback defaults needed for timeouts |
| ADR-05 | **Model fallback chain** (Flash → Flash Exp for vision; Flash → Pro for chat) | E-S | Resilience to 429/503; inconsistent quality across fallbacks |
| ADR-06 | **Zustand + persist on AsyncStorage as the database** | E-S | Simple; whole-blob writes; client-side `migrateSoilData`; no queries beyond in-memory filters |
| ADR-07 | **Defaults instead of errors when parsing AI output** | E-O | No crashes; fabricated health values; a wasted scan on bad input |
| ADR-08 | **Auto-save every identification** | E-O | No decision step for the user; junk records |
| ADR-09 | **Static bundled catalogues** (crops, products) | E-O | Offline; updates need a release; content errors persist |
| ADR-10 | **Quota-gated soft paywall via RevenueCat** (1 free scan; weekly trial preselected; lifetime option) | E-O | Conversion-optimised; entitlement logic outsourced |
| ADR-11 | **Two analytics stacks** (Firebase + PostHog) with surveys and flags | E-M, E-S | Funnel and experimentation; broader data footprint |
| ADR-12 | **Native crop step (uCrop) after capture** | E-O | The user frames the subject; one extra tap per scan |
| ADR-13 | **Pre-permission rationale screens** | E-O | Better grant rates; a clean denied state |
| ADR-14 | **Device-local identity, no account** | E-O, E-M | Zero friction; data lost with the device |
| ADR-15 | **Template-first product** (a generic identifier reskinned) | E-S, E-O | Fast to ship; leftover fields (valuation, age, materials) and placeholder strings |
