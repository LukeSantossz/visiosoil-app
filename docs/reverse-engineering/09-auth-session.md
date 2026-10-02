# 09 — Authentication and session

## Summary

There is **no user authentication**. No login screen, account or e-mail field
was observed, and the profile has no sign-out. **CONFIRMED** (E-O).

What stands in for a "session" is two anonymous identities and one entitlement:

```text
first launch
→ generate/obtain anonymous user id (stored in @soil_identifier_user)        [HIGHLY LIKELY]
→ RevenueCat configure                                                   [HIGHLY LIKELY]
→ RevenueCat identify ("🔄 Identifying user", "✅ User identified successfully")
→ initial purchase sync ("✅ Initial purchase sync completed")
→ CustomerInfo → isPremium / expirationDate ("🔍 Premium status analysis")
PostHog: anonymous_id / distinct_id, persisted by the SDK                  [HIGHLY LIKELY]
```

| Aspect | Behaviour | Label |
|---|---|---|
| Credential type | none for the user; how the app authenticates to its vendors is outside this study's scope (SPEC 0112) | CONFIRMED (no user credential, E-O) |
| Session duration | indefinite (device-bound) | INFERRED |
| Recovery | purchases recovered through "Restore Purchase" (store account); soil data has no cloud backup and no account (`allowBackup=false`); a device-to-device transfer on Android 12+ is not disabled by that attribute alone | CONFIRMED controls (E-O, E-M); transfer UNKNOWN |
| Refresh | entitlement re-checked at start-up and after purchase/restore; `expirationDate` normalised from string or Date (logs "🗓️ Converted string to Date") | HIGHLY LIKELY |
| Expiry | premium ends at the RevenueCat `expirationDate`; lifetime has none ("No expirationDate found in premium entitlement") | HIGHLY LIKELY |
| Logout | `Logging out…` / `✅ Logged out successfully` exists, most likely RevenueCat `logOut` during "Delete All Data" | INFERRED |
| Protected screens | none by identity. Feature gating comes only from the scan quota and premium status | CONFIRMED |
| Google Sign-In | `play-services-auth` and `SignInHubActivity` are linked, but no sign-in UI was found; probably transitive or unused | INFERRED |

No tokens, keys or identifiers were extracted or recorded.
