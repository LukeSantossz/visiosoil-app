# Deep dive — Collection and profile

## My Soils (collection)

| Aspect | Reconstruction | Label |
|---|---|---|
| Objective | Home: the saved soils at a glance | CONFIRMED |
| Screen | title "My Soil", "+" button, stats row (Total Soils, Avg Health, Favorites, This Month), "Search soil…", empty state ("No Soil Yet… tapping the camera icon", "Start Identifying"), 2-column cards (photo, type icon, chat and delete buttons, type, texture, health dot + %, confidence, relative date, crop tags) | CONFIRMED |
| State | collection store + derived stats (`getCollectionStats`, `soilsThisMonth`, `avgHealthScore`, `favoritesCount`) | HIGHLY LIKELY |
| Use case | `searchSoils`, `getRecentSoils`, `getFavoriteSoils`, `deleteSoil`, `toggleFavorite` | HIGHLY LIKELY |
| Persistence | AsyncStorage `@soil_collection` | HIGHLY LIKELY |
| Offline | fully functional | CONFIRMED |

## Profile

| Aspect | Reconstruction | Label |
|---|---|---|
| Screen | plan card ("Free Plan · N scans remaining", "Upgrade to Premium →"); stats (Total Soils, Avg Health, Top Type, Favorites); About (Help & Support, Terms of Service, Privacy Policy, Version 1.0.0); Danger Zone ("Delete All Data — Permanently delete all your data") | CONFIRMED |
| No settings | no language, units, theme or notification preferences | CONFIRMED |
| Wipe | clears AsyncStorage, the soil registry and the chat history, but preserves `scanCount`; probably logs RevenueCat out | HIGHLY LIKELY (E-S) |

## Call graph (wipe)

```text
Profile.deleteAll → confirm (UNKNOWN UI)
→ keep = userStore.scanCount                  ("💾 Will preserve scanCount (scans used)")
→ AsyncStorage.clear()                        ("🗑️ Cleared all AsyncStorage")
→ registry.clear()                            ("🗑️ Cleared soil registry")
→ userStore.reset({ scanCount: keep })        ("🗑️ Reset in-memory store with preserved scanCount")
→ purchases.logOut()?                         ("✅ Logged out successfully") [INFERRED]
```
