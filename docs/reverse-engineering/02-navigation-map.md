# 02 — Navigation map

## Navigation stack

- **React Navigation** with native screens: `react-native-screens` (`RNSScreenStack`, `RNSModalScreen`) behind a `StackNavigator`, and a `BottomTabNavigator` named `MainTabs`. **CONFIRMED** (E-S: `RootNavigator`, `MainTabs`, `StackNavigator`, `BottomTabNavigator`; E-N: `librnscreens.so`).
- One Android activity (`MainActivity`, `singleTask`) hosts everything. `UCropActivity` (crop) and the Play billing activities are the only other activities a user sees. **CONFIRMED** (E-M, E-P `mCurrentFocus`).
- No deep links: the manifest has only the launcher intent filter. **CONFIRMED** (E-M).

## Screen tree

```text
RootNavigator (stack)
├── OnboardingScreen                       [hasCompletedOnboarding == false]
│   ├── slide 1 "Identify Any Soil"
│   ├── AIConsentModal                     [on "Next" from slide 1]
│   │   ├── Cancel  → stays on onboarding  ("AI consent cancelled")
│   │   └── Continue → slide 2             ("AI consent given")
│   └── slide 2 "Grow Anything Coach" → "Get Started"
├── SocialProofScreen                      ("Navigating to SocialProof")         [CONFIRMED E-O, E-S]
├── PersonalizationScreen                  (0→100 % progress, no input, "Continue") [CONFIRMED E-O; "pacing device" INFERRED]
├── PaywallScreen (modal)                  [after personalisation; at 0 scans; "Upgrade to Premium"]
│   ├── TRY 3-DAY FREE → Google Play billing sheet (external activity)
│   ├── Restore Purchase
│   ├── Terms of Use / Privacy Policy      (external URLs)
│   └── ✕ close → previous screen / MainTabs
├── MainTabs (bottom tabs)
│   ├── My Soils  — CollectionScreen
│   │   ├── card → SoilDetailsScreen
│   │   ├── card chat icon → SoilChatScreen
│   │   ├── card trash → delete (confirmation UNKNOWN)
│   │   └── "+" / "Start Identifying" → Scanner (or image picker, INFERRED)
│   ├── Scanner   — ScannerScreen
│   │   ├── camera permission rationale → system dialog
│   │   ├── shutter → UCropActivity ("Crop Soil") → identification overlay → SoilDetailsScreen
│   │   ├── gallery → image picker + cropper
│   │   └── shutter at 0 scans → PaywallScreen (online) / back to My Soils (offline)
│   ├── Calculator — SoilCalculatorScreen (single screen, results inline)
│   └── Profile   — ProfileScreen
│       ├── Upgrade to Premium → PaywallScreen
│       ├── Help & Support / Terms / Privacy → external URLs
│       └── Delete All Data
├── SoilDetailsScreen
│   ├── ♥ favourite
│   ├── "Chat with AI to Refine Details" → SoilChatScreen
│   └── "Browse Compatible Crops" → CropPlanningScreen
├── SoilChatScreen
│   ├── quick prompt chips (first message only)
│   └── "View Full Details" → SoilDetailsScreen
├── CropPlanningScreen ("Grow Anything Coach", optimised for a soil type)
│   └── crop card → CropDetailsScreen
├── CropDetailsScreen
└── SurveyModal                            [PostHog survey matched; INFERRED trigger]
```

## Transition conditions

| From → To | Condition | Label |
|---|---|---|
| Launch → Onboarding | onboarding not completed (persisted flag) | HIGHLY LIKELY (E-S `hasCompletedOnboarding`, `setOnboardingComplete`; E-O after `pm clear`) |
| Launch → MainTabs | onboarding completed; a returning launch went straight to My Soils, with no paywall | CONFIRMED offline (E-O); online relaunch not tested |
| Slide 1 → consent modal | always, on the first "Next" | CONFIRMED (E-O) |
| Consent → slide 2 | consent accepted | CONFIRMED (E-O) |
| Personalisation → Paywall | always, on "Continue" | CONFIRMED (E-O) |
| Paywall close | always allowed (soft paywall) | CONFIRMED (E-O) |
| Shutter → crop → identify | scans remaining > 0 (or premium) | CONFIRMED (E-O) |
| Shutter → Paywall | scans remaining == 0, online | CONFIRMED (E-O) |
| Shutter → My Soils | scans remaining == 0, offline | CONFIRMED (E-O); cause INFERRED: the paywall cannot load offerings and dismisses |
| Identify → SoilDetails | always after a response, including a non-soil photo | CONFIRMED (E-O) |
| Details → Crops | always; the soil type is passed as the filter key | CONFIRMED (E-O "Optimized for Unknown") |

## Guards

- **No auth guard**: there is no signed-in area. **CONFIRMED**.
- **Entitlement guard** at the scanner, from the scan quota and premium status. **CONFIRMED**.
- **Consent guard**: AI features presumably require `aiConsent`. Cancelling keeps the user on onboarding. Whether the scanner re-asks later is **UNKNOWN**.
- **Permission guard**: the camera rationale view is rendered in place of the camera until permission is granted. **CONFIRMED**.

## Notes for automation

The paywall renders in a separate modal window that `uiautomator dump` does not
expose. A UI dump taken while it is visible still lists the screen underneath.
Screenshots are the reliable source for that screen.
