# 11 — Integrations

| Integration | Apparent reason | Components using it | Data involved | Dependencies | Label |
|---|---|---|---|---|---|
| **Google Gemini** (`@google/generative-ai`; 2.5 Flash primary, 2.0 Flash Exp backup, 2.5 Pro for chat fallback) | the whole "AI identification" and chat value | identification service, chat service | the user's photos (base64), chat text, soil context | Remote Config (model names) | HIGHLY LIKELY |
| **Firebase Remote Config** (+ A/B Testing) | ship model names and scan limits without a release; experiments | config service at start-up | config values | Firebase Installations | HIGHLY LIKELY |
| **Firebase Analytics** | acquisition and funnel analytics; auto screen reporting; ad ID and ad personalisation signals all default **on** | global | events, screen views, advertising ID | Measurement, AdServices | CONFIRMED (E-M flags) |
| **Firebase Crashlytics** (+ NDK, Sessions) | crash reporting | global | stack traces, session data | — | CONFIRMED present; manifest default off |
| **Firebase Cloud Messaging** | push re-engagement | messaging service | FCM token | Installations | CONFIRMED configured |
| **RevenueCat** (`react-native-purchases`; Play Billing 7.1.1; Amazon IAP) | subscriptions: weekly with 3-day trial, yearly, lifetime | paywall, profile, scanner gate | anonymous app user id, purchase receipts | Play Billing, Amazon Appstore | CONFIRMED (E-O billing flow, E-M) |
| `react-native-iap` | second IAP library | none observed | — | Play Billing | INFERRED leftover |
| **PostHog** (US/EU hosts) | product analytics, feature flags, in-app surveys, session-replay capable | analytics module, `SurveyModal` | events, person properties, survey answers | — | HIGHLY LIKELY |
| **Play In-App Review** (`storereview`) | rating prompt after "Help us improve" | social proof screen | — | Play Core | INFERRED |
| **Play licensing (pairip)** | anti-tamper / licence check | `LicenseContentProvider` at start-up | licence status | Play Store | CONFIRMED (E-M) |
| **VisionCamera** (+ CameraX extensions, ML Kit barcode) | in-app camera | scanner | camera frames | ML Kit (unused barcode) | CONFIRMED |
| **image-crop-picker** (uCrop) / **image-picker** | crop after capture; gallery import | scanner, "+" | image files | FileProviders | CONFIRMED (crop) |
| **Geolocation** (community) | optional location on records | not observed | coordinates | Play Services Location | INFERRED dormant |
| **Device info** | device metadata for analytics or support | analytics | model, OS, installer | — | INFERRED |
| **Retailers** (Amazon, Home Depot, Lowe's) | monetisation or utility links from the calculator | calculator | search query | browser | HIGHLY LIKELY |
| **Notifee** | local notifications | none observed | — | — | INFERRED dormant |
| **Lottie, Video, Sound** | onboarding or template media | none observed beyond animations | — | — | INFERRED |

## Privacy-relevant configuration (manifest defaults)

- `google_analytics_adid_collection_enabled=true`, `…ssaid_collection_enabled=true`, `…default_allow_ad_storage=true`, `…ad_user_data=true`, `…ad_personalization_signals=true`. **CONFIRMED** (E-M).
- `firebase_crashlytics_collection_enabled=false` by default, so crash collection is opted into at run time, if at all. **CONFIRMED** (E-M).
- AI processing disclosure through the consent modal before first use. **CONFIRMED** (E-O).
