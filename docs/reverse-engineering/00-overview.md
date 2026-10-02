# Reverse engineering: Soil Identifier (com.indiemobileapps.soilidentifier)

This folder reconstructs the technical documentation of a third-party Android app,
used only as an architectural reference for VisioSoil. No proprietary code is
reproduced here, no credential or secret was extracted, and no security mechanism
(license check, billing, certificate pinning, data sandbox) was bypassed.

## How the evidence was gathered

| Code | Source | What it can and cannot show |
|---|---|---|
| **E-M** | `AndroidManifest.xml` of the Play-installed APK, dumped with `aapt2` | Components, permissions, SDK registrars. Not what the JS layer does with them. |
| **E-D** | Class descriptors of `classes*.dex` (`dexdump`), names only | Which native libraries are linked. R8 obfuscates most names. |
| **E-N** | Native libraries in `split_config.x86_64.apk` | Runtime (React Native, Hermes, Fabric codegen). |
| **E-S** | The Hermes bytecode string table of `assets/index.android.bundle` (v96), parsed structurally | Identifiers, log messages, UI copy, URLs. Not control flow. Three credential-shaped strings were masked before reading and are not recorded anywhere. |
| **E-O** | Observed behaviour on an Android 35 emulator (Play image), from a clean install | Screens, transitions, error handling, offline behaviour. One real identification and one chat message were sent. |
| **E-P** | `dumpsys` (package, jobscheduler, alarm, notification) | Registered background work. |

Not used: decompiling the Hermes bytecode into source, traffic interception
(the app is not debuggable and a MITM certificate would mean defeating its trust
configuration), reading the app's private storage (`run-as` refused: not
debuggable), repackaging the APK (it carries a `pairip` license check).

## Confidence labels

- **CONFIRMED**: direct evidence (observed on screen, or present in the manifest).
- **HIGHLY LIKELY**: several independent pieces of evidence agree, e.g. a log string plus an identifier plus observed behaviour.
- **INFERRED**: an architectural hypothesis consistent with the evidence, but not proven by it.
- **UNKNOWN**: not enough information.

## The app in one paragraph

Soil Identifier is a **React Native (New Architecture, Hermes) client with no
first-party backend** (HIGHLY LIKELY: no first-party API host in the bundle). Image
identification sends the cropped photo **straight from the device to the Google Gemini
API** (HIGHLY LIKELY: Gemini host and SDK in the bundle, and the model described the
photo in the observed run), with the model names and scan
limits delivered by Firebase Remote Config. It renders the parsed JSON on a details
screen, with defaults filling the fields the model did not return in the observed
run (CONFIRMED), and stores
the result in a local collection persisted to AsyncStorage through a Zustand
store. Around that one feature sit a static crop catalogue with a soil
compatibility score, a soil volume calculator, a per-soil AI chat, and a
monetisation shell: onboarding, an AI-consent modal, a "social proof" screen, a
"personalizing" progress screen that collects no input (CONFIRMED), then a RevenueCat paywall with a 3-day
trial, a 1-scan free tier, and scan limits driven by Remote Config. Analytics and
experimentation go to Firebase and PostHog. Identifiers and the copy left in
the bundle ("valuation", "age estimate", "materials", placeholder keys) show the
app is a **reskin of a generic "AI identifier" template** (HIGHLY LIKELY). Each claim
here is detailed, with its label and evidence, in the documents mapped below.

## Headline facts

| Fact | Value | Label |
|---|---|---|
| Package / label | `com.indiemobileapps.soilidentifier` / "soilidentifier" | CONFIRMED (E-M, E-O) |
| Version | versionName 1.2, versionCode 3; Profile screen shows "1.0.0" | CONFIRMED (E-M, E-O) |
| SDK | min 24, target 35, compile 35; AGP 8.8.0 | CONFIRMED (E-M) |
| UI runtime | React Native, New Architecture (`libappmodules.so`, `libreact_codegen_*`), Hermes bytecode v96 | CONFIRMED (E-N, E-S) |
| Expo | No `expo.modules` classes; bare React Native CLI project | HIGHLY LIKELY (E-D) |
| First-party Kotlin/Java code | 3 classes under the app package: `MainActivity`, `MainApplication` and an inner class of it | CONFIRMED (E-D) |
| Backend | None first-party. Gemini, Firebase, RevenueCat, PostHog | HIGHLY LIKELY (E-S, E-O) |
| Auth | No login. Anonymous IDs (RevenueCat app user, PostHog distinct id) | HIGHLY LIKELY (E-S, E-O) |
| Offline | Collection, chat history, crop catalogue and calculator work offline; identification and chat need the network | CONFIRMED (E-O) |
| Locale | UI in English only; prices localised by Play (BRL) | HIGHLY LIKELY (E-S, E-O) |

## Document map

| File | Content |
|---|---|
| [01-feature-inventory.md](01-feature-inventory.md) | Every feature, its gate and its status |
| [02-navigation-map.md](02-navigation-map.md) | Screen tree, transitions and their conditions |
| [03-system-architecture.md](03-system-architecture.md) | Layers, runtime, structural map, Mermaid diagram |
| [04-module-dependencies.md](04-module-dependencies.md) | Inferred JS modules and their dependency graph |
| [05-domain-model.md](05-domain-model.md) | Entities, AI response shape, ER diagram |
| [06-data-layer.md](06-data-layer.md) | Persistence, keys, migrations, invalidation |
| [07-network-layer.md](07-network-layer.md) | External endpoints, retries, model fallback |
| [08-state-management.md](08-state-management.md) | Zustand stores, local state, effects |
| [09-auth-session.md](09-auth-session.md) | Anonymous identity and entitlement "session" |
| [10-background-processing.md](10-background-processing.md) | What runs without the UI |
| [11-integrations.md](11-integrations.md) | SDK catalogue |
| [12-business-rules.md](12-business-rules.md) | Explicit rules |
| [13-feature-deep-dives/](13-feature-deep-dives/) | Vertical slices of the main features |
| [14-sequence-diagrams.md](14-sequence-diagrams.md) | Sequence diagrams of the key flows |
| [15-architectural-decisions.md](15-architectural-decisions.md) | Inferred ADRs |
| [16-comparison-with-target-project.md](16-comparison-with-target-project.md) | What VisioSoil should adopt, adapt, study or discard |
| [17-derived-backlog.md](17-derived-backlog.md) | Backlog candidates for VisioSoil |
| [18-open-questions.md](18-open-questions.md) | What is still unknown and how to find out |

## Answers to the guiding questions (short form)

- **How does it start?** `MainApplication` loads React Native and Hermes. Content providers initialise Firebase, Crashlytics, ML Kit, Notifee and WorkManager before any JS runs. Then the JS root reads persisted stores, fetches Remote Config with a timeout and a fallback, initialises RevenueCat and i18n, and routes to onboarding or to the tabs. See [03](03-system-architecture.md#bootstrap).
- **Where are data fetched?** Only from Gemini (identification, chat), Remote Config (models, limits), RevenueCat (offerings, entitlements) and PostHog (flags, surveys). Everything soil-related is created on the device from a Gemini response.
- **Where are data stored?** AsyncStorage, as Zustand-persisted JSON blobs (`@soil_collection`, `@soil_identifier_user`) plus SDK-owned keys. See [06](06-data-layer.md).
- **What happens when the connection drops?** The collection, chat history, crops and calculator keep working. Identification at zero scans silently returns to the home tab instead of showing the paywall or an error. A chat message answers with a generic apology bubble. See [12](12-business-rules.md).
- **What runs in the background?** Nothing the app defines. Firebase telemetry upload jobs, an FCM receiver and dormant Notifee and WorkManager infrastructure. See [10](10-background-processing.md).
