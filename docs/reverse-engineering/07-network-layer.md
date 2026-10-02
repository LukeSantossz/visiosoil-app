# 07 — Network layer

No traffic was intercepted. Everything here comes from the URLs and identifiers
in the bundle (E-S), the SDK registrars (E-M) and observed behaviour (E-O).

## Style

- **No first-party API.** No custom REST, GraphQL, WebSocket or gRPC base URL exists in the bundle. The only own-domain URLs are web pages: contact, privacy policy, terms. **HIGHLY LIKELY** (E-S).
- All networking goes through **vendor SDKs** over HTTPS (Gemini SDK, Firebase, RevenueCat, PostHog). `okhttp3` is present, used by those SDKs.

## Endpoint inventory

| Service | Host | Called from | Purpose | Label |
|---|---|---|---|---|
| Google Gemini | `generativelanguage.googleapis.com` (`models/…:generateContent`, `streamGenerateContent`) | identification service, chat service | vision identification, chat | CONFIRMED host (E-S); call observed indirectly (the model described the image, E-O) |
| Firebase Remote Config | Firebase endpoints | config service | `primary_model`, `backup_model`, scan limits | HIGHLY LIKELY (E-S) |
| Firebase Analytics / Measurement | Google endpoints | analytics | events, automatic screen reporting, ad ID | CONFIRMED configured (E-M) |
| Firebase Crashlytics + Sessions | Google endpoints | crash reporting | crashes (manifest default `collection_enabled=false`; may be enabled at run time via `setCrashlyticsCollectionEnabled`) | CONFIRMED present (E-M) |
| Firebase Cloud Messaging | Google endpoints | messaging | push (auto-init on) | CONFIRMED configured (E-M) |
| Firebase A/B Testing | Google endpoints | Remote Config experiments | experiments | CONFIRMED registrar (E-M) |
| RevenueCat | RevenueCat API; `errors.rev.cat` for error docs | purchases service | offerings, customer info, purchase sync | HIGHLY LIKELY (E-S, E-D) |
| Google Play Billing 7.1.1 / Amazon IAP | on-device stores | RevenueCat | purchase UI | CONFIRMED (E-M, E-O billing sheet) |
| PostHog | `us.i.posthog.com` / `eu.i.posthog.com` (+ assets hosts) | analytics | events, feature flags, surveys, possibly session replay | HIGHLY LIKELY (E-S) |
| Retailers | `amazon.com/s?k=…`, `homedepot.com/s/…`, `lowes.com/search?…` | calculator products | external browser links | HIGHLY LIKELY (E-S) |
| Publisher site | `indiemobileapps.com/{contact,privacy-policy,terms}` | profile | web pages | HIGHLY LIKELY (E-S) |

## Identification request (conceptual)

```text
POST https://generativelanguage.googleapis.com/…/models/{primary_model}:generateContent
body: { contents: [ { parts: [ {text: <instruction prompt>}, {inlineData: {mimeType: "image/jpeg", data: <base64>}} … ] } ],
        generationConfig: { temperature, … }, safetySettings: […], systemInstruction? }
→ candidates[0].content.parts[0].text  (JSON as text)  → parse → soils array → first soil
```

`primary_model` defaults to `gemini-2.5-flash`. On HTTP **503 or 429** the
service retries once with the backup (logged as "Gemini 2.0 Flash Exp"). Chat
falls back from Flash to `gemini-2.5-pro`. **HIGHLY LIKELY** (E-S:
"⚠️ Flash model unavailable (503/429), retrying with Gemini 2.0 Flash Exp…",
"⚠️ Flash model unavailable for chat, retrying with Pro…", model id strings).

The response is parsed from text ("📝 Raw Gemini response received",
"✨ Parsed AI result", "🌱 Parsed soils array") into a **soils array**, so the
prompt asks for one or more candidates and the app keeps the first.
**HIGHLY LIKELY**.

## Errors, retries, timeouts

| Concern | Behaviour | Label |
|---|---|---|
| Model overloaded / rate limited | one fallback-model retry | HIGHLY LIKELY |
| Model returns "not soil" | **not treated as an error**: the record is saved with defaults (Unknown, 50/100, pH 7) and a scan is consumed | CONFIRMED (E-O) |
| Chat failure | rendered as an assistant bubble "I'm having trouble processing that. Could you rephrase or try a different question?" | CONFIRMED (E-O) |
| Remote Config timeout | falls back to bundled defaults | HIGHLY LIKELY (E-S) |
| RevenueCat offerings missing | "No current offering found"; offline at 0 scans the paywall did not stay on screen | CONFIRMED behaviour (E-O); cause INFERRED |
| Timeouts | SDK defaults; `getRecommendedTimeoutMillis` exists in the SDK | UNKNOWN for app-level values |
| Offline detection | `ACCESS_NETWORK_STATE` declared; no "you are offline" UI observed | CONFIRMED absent in UI (E-O) |

## Caching, pagination, versioning

None observed in the tested flows: single request/response calls, no paginated lists.
The SDK's streaming methods (`streamGenerateContent`) are in the bundle; whether the
app uses them is UNKNOWN.
Model versioning is the only "API version" lever, and it is controlled
remotely through Remote Config (`primary_model`, `backup_model`).
**HIGHLY LIKELY**.

## Design observations

- A client-direct AI integration means the client itself must authenticate to the AI provider. How this app does so is outside the scope of this document; the general lesson for VisioSoil is in [16](16-comparison-with-target-project.md) (C13, C14).
- Placeholder strings (`your_revenuecat_google_key_here`, `your-privacy-policy-url.com/privacy`) are left in the bundle as template fallbacks. **CONFIRMED** present (E-S).
