# 10 — Background processing

## Registered at the time of observation (E-P)

| Mechanism | What was registered | Owner | Label |
|---|---|---|---|
| JobScheduler | several `JobInfoSchedulerService` jobs | Firebase datatransport (batched telemetry upload for Analytics, Crashlytics and Sessions) | CONFIRMED |
| AlarmManager | none for the package | — | CONFIRMED |
| Notification channels | none created | — | CONFIRMED |
| Foreground service | none running | — | CONFIRMED |

## Present but dormant infrastructure (E-M)

| Component | Trigger | Effect when used | Label |
|---|---|---|---|
| WorkManager (initialised through androidx.startup) | app-scheduled work | none observed; likely a transitive dependency (Firebase, Notifee) | INFERRED |
| Notifee (`ForegroundService` type 0x800 = `shortService`, reboot, alarm-permission and block-state receivers) | local notification scheduling | could deliver reminders (e.g. crop season alerts); never asked for POST_NOTIFICATIONS in the observed flows | INFERRED dormant |
| FCM (`ReactNativeFirebaseMessagingService`, headless JS service, `FirebaseInstanceIdReceiver`) | server push | remote marketing or re-engagement push; auto-init enabled, so an FCM token is minted | CONFIRMED configured; usage UNKNOWN |
| `RECEIVE_BOOT_COMPLETED` | boot | Notifee / WorkManager reschedule | CONFIRMED declared |
| `SCHEDULE_EXACT_ALARM` | exact alarms | Notifee triggers | CONFIRMED declared |
| Install referrer + AD_ID + AdServices attribution | install | attribution for acquisition campaigns | CONFIRMED declared |

## App-level background work

None. Identification and chat run in the foreground on the JS thread; the image
work (crop, base64) runs in native modules. No uploads, downloads or periodic
sync exist, because there is no backend to sync with. **HIGHLY LIKELY**.
