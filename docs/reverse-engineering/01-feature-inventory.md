# 01 — Feature inventory

Gate column: **Free** = available on the free plan, **Scan** = consumes a scan
from the quota, **Net** = needs connectivity.

| # | Feature | Screen(s) | Gate | Status | Label | Evidence |
|---|---|---|---|---|---|---|
| F1 | Onboarding carousel (2 slides: "Identify Any Soil", "Grow Anything Coach") | `OnboardingScreen` | Free | Live | CONFIRMED | E-O, E-S (`HandleNext called, currentStep`) |
| F2 | AI consent modal ("AI-Powered Features", Cancel / Continue, "Learn more") | `AIConsentModal` | Free | Live, shown between slide 1 and 2 | CONFIRMED | E-O, E-S (`AI consent given`, `aiConsent`) |
| F3 | Social proof / review ask ("Help us improve") | `SocialProofScreen` | Free | Live | CONFIRMED (screen); store review prompt INFERRED | E-O, E-S (`requestReview`, `requestStoreReview`, `com/oblador/storereview`) |
| F4 | Fake personalisation progress ("Personalizing Your Experience", 0→100 %) | `PersonalizationScreen` | Free | Live | CONFIRMED | E-O |
| F5 | Paywall (weekly with 3-day trial, yearly, lifetime "holiday sale"; trial toggle; restore; terms; privacy) | `PaywallScreen` (modal) | Free to view | Live | CONFIRMED | E-O, E-S (RevenueCat identifiers) |
| F6 | Soil collection home: stats (total, avg health, favourites, this month), search, grid of cards, "+" to add | `CollectionScreen` (tab "My Soils") | Free, offline | Live | CONFIRMED | E-O |
| F7 | Camera scanner with framing guide, flash, gallery button, remaining-scan badge | `ScannerScreen` (tab "Scanner") | Scan, Net | Live | CONFIRMED | E-O |
| F8 | Pre-permission rationale for the camera | inside `ScannerScreen` | Free | Live | CONFIRMED | E-O |
| F9 | Crop step after capture (native uCrop, "Crop Soil") | `UCropActivity` | — | Live | CONFIRMED | E-O, E-M |
| F10 | Identification with progress overlay ("Identifying Soil… Analyzing image with AI") | `ScannerScreen` overlay | Scan, Net | Live | CONFIRMED | E-O, E-S |
| F11 | Multi-photo identification | scanner | Scan, Net | Present in code; not observed in UI | INFERRED | E-S (`identifySoilFromImages`, `imageUris`, `multiPhotoBadge`, `Converting image(s)`) |
| F12 | Soil details: type, texture, confidence, health score, fertility, water retention, pH, organic matter, compaction, condition, "materials", description, "age estimate" | `SoilDetailsScreen` | Free, offline | Live | CONFIRMED | E-O |
| F13 | Favourite / unfavourite a soil | details header, card | Free, offline | Live | CONFIRMED (control); toggling not exercised | E-O, E-S (`toggleFavorite`) |
| F14 | Delete one soil | card trash icon | Free, offline | Live | CONFIRMED (control); not exercised | E-O, E-S (`Soil deleted:`) |
| F15 | Per-soil AI chat with quick prompts and persisted history | `SoilChatScreen` | Free, Net | Live | CONFIRMED | E-O, E-S (`saveChatHistory`, `conversationHistory`) |
| F16 | Crop catalogue ("Grow Anything Coach"): search, category and season filters, sorted by compatibility | `CropPlanningScreen` | Free, offline | Live (41 crops listed; onboarding promises "50+") | CONFIRMED | E-O |
| F17 | Crop details: growth time, yield, sunlight, water, nitrogen need, preferred soil types, pH range, seasons, a "not ideal for X" warning | `CropDetailsScreen` | Free, offline | Live | CONFIRMED | E-O |
| F18 | Soil volume calculator (rectangular L×W×D, circular π×R²×D; imperial/metric), bag estimate, cost range, product recommendations | `SoilCalculatorScreen` (tab "Calculator") | Free, offline | Live | CONFIRMED | E-O |
| F19 | Retailer links (Amazon, Home Depot, Lowe's search URLs) for recommended products | calculator results | Free, Net | Present; tap not exercised | HIGHLY LIKELY | E-S (URLs per product type) |
| F20 | Profile: plan card ("Free Plan · N scans remaining", Upgrade), stats, Help & Support, Terms, Privacy, Version | `ProfileScreen` | Free | Live | CONFIRMED | E-O |
| F21 | Delete All Data (keeps the scan counter) | Profile "Danger Zone" | Free | Live; not exercised | CONFIRMED (control); counter kept HIGHLY LIKELY | E-O, E-S (`Reset in-memory store with preserved scanCount`) |
| F22 | Restore purchases | paywall | Net | Live; not exercised | CONFIRMED (control) | E-O, E-S |
| F23 | In-app surveys | `SurveyModal` | Free, Net | Present (PostHog surveys) | HIGHLY LIKELY | E-S (`getActiveMatchingSurveys`, `surveyPopupDelaySeconds`) |
| F24 | Push notifications | — | — | Infrastructure present; POST_NOTIFICATIONS never requested in the observed flows | INFERRED dormant | E-M, E-P |
| F25 | Location capture | — | — | Permission declared; never requested in the observed flows | INFERRED optional or dormant | E-M, E-S (`requestLocationPermission`, `shareLocation`) |
| F26 | Barcode scanning | — | — | ML Kit barcode linked through VisionCamera's code scanner; no UI | INFERRED unused | E-M, E-S (`useCodeScanner`) |
| F27 | Valuation / market value / age estimate | details shows "Age Estimate N/A", "Materials" | — | Leftover from the template | HIGHLY LIKELY | E-O, E-S (`Valuation updated: ${{min}} - ${{max}}`, `marketValue`) |
| F28 | Video and sound playback | — | — | `react-native-video` (ExoPlayer) and `react-native-sound` linked; no UI seen | INFERRED onboarding or template assets | E-D |

## Feature clusters

```text
Acquisition & monetisation  F1 F2 F3 F4 F5 F20 F22 F23
Core value                  F7 F8 F9 F10 F11 F12 F13 F14
Engagement                  F6 F15 F16 F17
Utility                     F18 F19
Data rights                 F21
Dormant / template          F24 F25 F26 F27 F28
```

The core is one AI call. Everything else is either a static local dataset
(crops, products), pure arithmetic (calculator) or conversion funnel.
