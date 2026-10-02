# 08 — State management

## Mechanisms

| Mechanism | Scope | Evidence | Label |
|---|---|---|---|
| Zustand stores + `persist` (AsyncStorage) + `subscribeWithSelector` | global, persisted | `subscribeWithSelector(Impl)`, `skipHydration`, `@soil_collection`, `@soil_identifier_user` | HIGHLY LIKELY |
| In-memory registry with query helpers | global, derived | `soilRegistry`, `addSoilToRegistry`, `getAllSoils called before initialization` | HIGHLY LIKELY |
| React Context | chat | `useChatContext` | HIGHLY LIKELY |
| Component state / hooks | forms (calculator), progress, camera, modals | E-O | CONFIRMED behaviour |
| Reanimated shared values | animations only | `useSharedValue`, worklets | CONFIRMED (library) |

No Redux, MobX, RxJS or React Query found. **HIGHLY LIKELY** (no identifying strings).

## Stores (reconstructed)

```text
collectionStore (persisted @soil_collection)
  state:   soils[], favorites (derived), stats (derived: total, avg health, favourites, this month/year)
  actions: addSoil / addSoilToCollection, updateSoil(InCollection), removeSoil(FromCollection),
           toggleFavorite, clearCollection, migrateSoilData
userStore (persisted @soil_identifier_user)
  state:   userId, scanCount, scansRemaining, scanLimit, hasCompletedOnboarding, aiConsent
  actions: incrementScanCount, decrementScansRemaining, resetScansRemaining,
           updateScanLimitsFromRemoteConfig, setOnboardingComplete
premiumStore (mirror of RevenueCat)
  state:   isPremium, expirationDate, activeEntitlementKeys, currentOffering
  actions: checkPremiumStatus, setPremium, updateSubscriptionInfo
chat (context + persisted history per soil)
  state:   conversationHistory, loading
  actions: sendMessage, saveChatHistory, validateChatHistory
```

## Event → action → state → UI (identification)

```text
Event    tap shutter
Guard    canScanMore = isPremium || scansRemaining > 0       → else open Paywall
Action   takePhoto → openCropper → identifySoilFromImages
Effect   Gemini call (+ fallback); progress % animates
Reducer  addSoil(parsed + defaults); incrementScanCount; decrementScansRemaining
UI       navigate SoilDetails(soilId); the collection grid and stats update through subscriptions
```

## Cross-cutting state concerns

| Concern | How it is handled | Label |
|---|---|---|
| Loading | full-screen overlay with a % progress bar and status text ("Processing image…", "Complete!") | CONFIRMED (E-O) |
| Progress realism | jumps 1 % → 7 % → 15 % → 100 %, consistent with a timer-driven fake progress that snaps on completion | INFERRED |
| Error | identification: a failure is either swallowed into defaults or logged ("❌ Soil identification failed"); chat: an apology bubble | CONFIRMED (E-O) for both visible outcomes |
| Retry | automatic model fallback once; no user-facing retry button seen | CONFIRMED absent (E-O) |
| Optimistic updates | chat: the user bubble and typing indicator appear before the reply | CONFIRMED (E-O) |
| Refresh | entitlement refresh at start and after purchase/restore; limits from Remote Config at start | HIGHLY LIKELY (E-S) |
| Invalidation | none needed (local data); Remote Config `on_config_updated` listener available | INFERRED |
| Global vs local | quota, collection, premium and flags are global; screen inputs are local | INFERRED |

## Derived state that drifted

The Profile and the collection stats are both derived from the same store and
agreed (1 soil, average health 50, 0 favourites, 1 this month). **CONFIRMED** (E-O).
The version label ("1.0.0") is a constant that does not follow `versionName`
(1.2). **CONFIRMED** (E-O, E-M).
