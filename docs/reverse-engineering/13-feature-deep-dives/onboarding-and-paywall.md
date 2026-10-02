# Deep dive — Onboarding, consent and paywall

| Aspect | Reconstruction | Label |
|---|---|---|
| Objective | Explain the value, collect AI consent, ask for a rating, then convert to a trial | CONFIRMED |
| Entry | first launch (or after clearing data) | CONFIRMED |
| Screens | Onboarding slide 1 → AIConsentModal → slide 2 → SocialProof ("Help us improve": 4 bullet reasons, Continue) → Personalization (animated shovel, 0→100 %, "Ready…", Continue) → Paywall modal | CONFIRMED |
| Paywall content | "ULTIMATE SOIL EXPERT 🌱"; benefits (unlimited identifications, advanced health analysis, save and manage collection, offline access); "Show More"; plans R$26.99/week ("Start using for free", preselected), R$104.99/year ("Value for money"), LIFETIME R$159.99 ("HOLIDAY SEASON SALE", one-time); "Auto-renewable. Cancel anytime."; "Not sure yet?" + "Enable 3-day free trial" toggle; CTA "TRY 3-DAY FREE 🤲"; Terms · Privacy · Restore | CONFIRMED (E-O, prices from the Play BRL storefront) |
| State | `currentStep`, `aiConsent`, `hasCompletedOnboarding`; paywall: offerings, selected package, `freeTrial` toggle | HIGHLY LIKELY |
| Controller | `HandleNext`, `HandleGetStarted`, `handleConsentContinue/Cancel`, `handlePackageSelection`, `handleFreeTrialToggle` | HIGHLY LIKELY |
| Use case | purchases service: `loadOfferings`, `purchasePackage`, `restorePurchases`, `checkTrialOrIntroductoryPriceEligibility` | HIGHLY LIKELY |
| API | RevenueCat → Play Billing; Amazon path present | CONFIRMED (billing sheet observed) |
| Persistence | onboarding/consent flags, premium mirror | HIGHLY LIKELY |
| Rules | BR-06…08, BR-12 | — |
| Side effects | analytics funnel events; store review request; RevenueCat attribute sync | INFERRED |
| Errors | purchase cancelled → back to the paywall; offerings unavailable → paywall dismisses (offline) | CONFIRMED / INFERRED |
| Output | trial started (not done here) or the paywall closed → MainTabs | CONFIRMED (close) |

## Call graph

```text
Onboarding.next(step 0) → show AIConsentModal
  Continue → aiConsent = true → step 1
  Cancel   → stay
Onboarding.getStarted → navigate(SocialProof)
SocialProof.continue → (requestReview?) → navigate(Personalization)
Personalization.continue → setOnboardingComplete() (I) → present(Paywall)
   (the flag is set by the end of this step: after closing the paywall, a relaunch opened MainTabs)
Paywall.mount → purchases.loadOfferings() → render packages (weekly preselected)
Paywall.cta → purchases.purchasePackage(selected) → Play Billing sheet
   ├─ success → checkPremiumStatus → isPremium → close
   └─ cancel  → stay on paywall
Paywall.close → MainTabs
```

## Funnel design notes

- The "personalizing" screen personalises nothing visible: no question was asked before it. It is a pacing device before the paywall. **CONFIRMED** (no inputs collected, E-O).
- The preselected weekly plan with a trial is the most expensive per year (R$26.99 × 52 ≈ R$1,403, against R$104.99 per year).
- These patterns are documented to be **avoided**, not copied; see [16](../16-comparison-with-target-project.md).
