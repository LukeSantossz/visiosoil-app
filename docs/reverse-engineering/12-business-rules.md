# 12 — Business rules

Each rule has an ID, a statement, a label and its evidence.

## Quota and monetisation

| ID | Rule | Label | Evidence |
|---|---|---|---|
| BR-01 | A free user gets **1** identification. | CONFIRMED | E-O ("1 scans remaining" → "0 scans remaining") |
| BR-02 | The free limit (and probably a premium cap) comes from Remote Config, with bundled defaults. | HIGHLY LIKELY | E-S (`updateScanLimitsFromRemoteConfig`, `getFreeScanLimit`, `SCAN_LIMITS`, `PREMIUM_SCANS`, "Remote config max limit") |
| BR-03 | A scan is consumed **even when the photo is not soil** and the result is "Unknown, 0 % confidence". | CONFIRMED | E-O |
| BR-04 | At 0 scans, online, the shutter opens the paywall instead of the camera flow. | CONFIRMED | E-O |
| BR-05 | At 0 scans, offline, the shutter returns to My Soils with no message. | CONFIRMED | E-O |
| BR-06 | The paywall is soft: it can always be closed. | CONFIRMED | E-O |
| BR-07 | The paywall is shown once in onboarding, unconditionally, after the personalisation screen. | CONFIRMED | E-O |
| BR-08 | The default selection is the weekly plan with the 3-day trial. | CONFIRMED | E-O (weekly highlighted, "TRY 3-DAY FREE") |
| BR-09 | "Delete All Data" preserves the used-scan counter, so wiping cannot refill the free quota. | HIGHLY LIKELY | E-S |
| BR-10 | Premium = an active RevenueCat entitlement; lifetime has no expiration date. | HIGHLY LIKELY | E-S |
| BR-11 | Chat is **not** gated by premium or quota. | CONFIRMED | E-O (worked at 0 scans on the free plan) |

## Consent and permissions

| ID | Rule | Label | Evidence |
|---|---|---|---|
| BR-12 | AI consent is requested during onboarding, before the second slide; cancelling keeps the user in onboarding. | CONFIRMED | E-O |
| BR-13 | The camera permission is preceded by an in-app rationale screen; the system dialog appears only after "Continue". | CONFIRMED | E-O |
| BR-14 | Location and notifications are never requested in the core flows. | CONFIRMED (for the flows exercised) | E-O, E-P |

## Identification and results

| ID | Rule | Label | Evidence |
|---|---|---|---|
| BR-15 | Every capture goes through a crop step before identification. | CONFIRMED | E-O |
| BR-16 | Fields the model did not supply are filled with defaults: health 50, fertility 50, water retention 50, compaction 50, pH 7 (Neutral), organic matter Medium, texture Medium, condition Fair. | CONFIRMED | E-O |
| BR-17 | There is no out-of-distribution rejection: a non-soil image yields a saved record. | CONFIRMED | E-O |
| BR-18 | Every identification is auto-saved to the collection. There is no "save" step. | CONFIRMED | E-O |
| BR-19 | Suitable-crop tags are shown even for an unknown soil. | CONFIRMED | E-O ("Vegetables", "Herbs") |
| BR-20 | On model overload (503/429) the service retries once with a backup model. | HIGHLY LIKELY | E-S |
| BR-21 | The first chat message is a local summary template; later turns go to the model with the soil as context. | CONFIRMED (template) / INFERRED (context) | E-O, E-S |
| BR-22 | Quick-prompt chips are offered only before the first user message. | CONFIRMED | E-O |

## Crops and calculator

| ID | Rule | Label | Evidence |
|---|---|---|---|
| BR-23 | Crops are ranked by a compatibility score against the soil type; an unknown soil gives 50 % for every crop. | CONFIRMED | E-O |
| BR-24 | A crop shows "Not ideal for {soil}. Consider soil amendments." when the soil type is not among its preferred types. | CONFIRMED | E-O |
| BR-25 | Calculator: rectangular V = L × W × D; circular V = π × R² × D; D is entered in cm (metric) or in (imperial). | CONFIRMED | E-O (3 × 3 m × 30 cm = 2 700 L = 95.35 cu ft) |
| BR-26 | Metric mode requires length and width ≥ **2.5 m**, which looks like an imperial-scale bound reused for metres. Validation runs on submit and errors persist until the next submit. | CONFIRMED (behaviour) / INFERRED (cause) | E-O |
| BR-27 | Results always show cubic feet, cubic yards, litres and gallons, then bag counts in cu ft and costs in USD, whatever the unit system or the store currency. | CONFIRMED | E-O |
| BR-28 | The calculate button is disabled until all fields are filled (`calculateButtonDisabled`). | CONFIRMED | E-O, E-S |

## Data rights

| ID | Rule | Label | Evidence |
|---|---|---|---|
| BR-29 | All user data is device-local; no account, no cloud backup (`allowBackup=false`). | HIGHLY LIKELY | E-M, E-S |
| BR-30 | The user can delete one record or all data from Profile. | CONFIRMED (controls) | E-O |

## In the requested format

```text
Unauthenticated user (everyone)
→ can browse the collection, crops, calculator and profile offline
→ can chat about any saved soil (online)
→ can identify while scansRemaining > 0 (free: 1)
→ cannot identify at 0 scans → paywall (online) / silently nothing (offline)

Premium user (RevenueCat entitlement active)
→ identification unlocked (possibly capped by a remote PREMIUM_SCANS value)

Soil record in any state
→ chat, favourite, delete, browse crops available
→ no "re-identify", no edit of fields observed
```
