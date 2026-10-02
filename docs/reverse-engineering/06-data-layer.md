# 06 — Data layer

## Storage technologies

| Technology | Used by | Label |
|---|---|---|
| **AsyncStorage** (`@react-native-async-storage`; SQLite-backed on Android by the library's implementation, not observed directly) | App state: Zustand-persisted stores; PostHog and survey keys | CONFIRMED present (E-D); app usage HIGHLY LIKELY (E-S) |
| Room | WorkManager's internal database (`MultiInstanceInvalidationService`) | HIGHLY LIKELY library-owned (E-M) |
| Jetpack DataStore (`libdatastore_shared_counter.so`) | Firebase SDKs (sessions, settings) | HIGHLY LIKELY library-owned (E-N) |
| Files | Cropped photos written by the image-crop-picker; FileProviders `imagepickerprovider` and `provider` | HIGHLY LIKELY (E-M) |
| SharedPreferences | Firebase, RevenueCat, PostHog internals | INFERRED |
| Secure storage | None found (no Keystore-backed storage library) | HIGHLY LIKELY absent (E-D) |

The app has **no relational schema of its own**.

## Keys and records

| Key / store | Content | Label |
|---|---|---|
| `@soil_collection` | the soil records (JSON array, Zustand `persist`) | HIGHLY LIKELY (E-S) |
| `@soil_identifier_user` | user/scan state: user id, `scanCount`, `scansRemaining`, onboarding and consent flags, premium mirror | HIGHLY LIKELY (E-S) |
| chat history | per-soil conversation (`saveChatHistory`) | CONFIRMED persisted (E-O); key name UNKNOWN |
| `survey_last_seen_date`, `surveys_seen` | PostHog survey throttling | HIGHLY LIKELY (E-S) |
| PostHog keys (`anonymous_id`, `distinct_id`, `feature_flags`, `session_id`…) | SDK state | HIGHLY LIKELY (E-S) |
| `@react-native-firebase:` prefix | RN Firebase persisted settings | HIGHLY LIKELY (E-S) |

Reading the values was not possible (not debuggable) and was not attempted any
other way.

## Mapping to the Entity / DAO / Repository / Database pattern

```text
Entity       → plain JS object (Soil, ChatMessage, UserState)
DAO          → none; Zustand actions (addSoil, updateSoil, deleteSoil, toggleFavorite, clearCollection)
Repository   → none; a "registry" module offers query helpers over the in-memory list
Database     → AsyncStorage key holding a serialised JSON blob per store
```

Every write re-serialises the whole store. With images stored as paths, not
inline base64, this stays small for a typical collection. **INFERRED**.

## Persistent vs temporary

| Data | Lifetime |
|---|---|
| Soil records, favourites, chat history, scan counter, onboarding and consent flags | persistent (until "Delete All Data" or uninstall; `allowBackup=false` → not restored on a new device) |
| Remote Config values | SDK cache, refreshed at start-up |
| RevenueCat `CustomerInfo` / offerings | SDK cache |
| Identification progress, camera state, form inputs | component state, transient |
| Cropped image files | persistent as long as the record points to them (whether they are copied out of the cache directory is UNKNOWN) |

## Invalidation and migration

- **Client-side data migration** exists: `migrateSoilData` (E-S). It is most likely a Zustand `persist` `version`/`migrate` hook upgrading old record shapes. **INFERRED**.
- **Rehydration ordering guard**: "getAllSoils called before initialization" shows the registry must be hydrated before it is queried, and logs (rather than awaits) when it is not. **HIGHLY LIKELY**.
- **No cache invalidation** is needed for soil data: records never come from a server.
- **Wipe semantics**: "Delete All Data" clears AsyncStorage (`Cleared all AsyncStorage`) but **re-writes the scan counter** (`Will preserve scanCount (scans used)`, `Restored fresh state with scanCount`), so wiping does not reset the free quota. **HIGHLY LIKELY** (E-S; not exercised).

## Local/remote synchronisation

None for domain data. The only synchronisation is entitlement state with
RevenueCat ("Purchases synced with backend", "Initial purchase sync completed")
and quota limits from Remote Config. The device is the single source of truth
for soils. A lost device means a lost collection (no backup, no account).
