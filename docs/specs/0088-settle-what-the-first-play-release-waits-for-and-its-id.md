# SPEC: chore(release): settle what the first play release waits for and the id it ships under

## Problem

Step 1 of the Google Play epic (#265) left open three decisions that every later
step reads, and the Developer took them on 2026-09-29, so they have to be
recorded where later work finds them and the permanent id applied before any
upload:

- whether v1 waits for classification (#266);
- whether it ships Google sign-in (#273);
- which application id it is published under (#267).

## Design Decision

**The first Play release waits for classification (ADR 0026).** It ships only
when a photograph taken in the app gets a texture class. That means the
A4-sheet reader measures a scale on the device, and the descriptor path runs
on what it measured. The field-notebook-first release is not taken.

The product the README, the onboarding and the listing describe is soil texture
classification. A release without it would have to rewrite all three for a
different product (#281, #282, #294). It would also collect ratings on that
product, and ratings stay on the listing.

**What the listing may claim.** The listing names the classes the model
distinguishes, and says the result is an estimate with a confidence. It claims
**no accuracy figure** until one has been measured on photographs captured the
way the app captures them. E0's figures exist:

- group accuracy 0.6883 and photograph macro-F1 0.6232 (`docs/ml/e0-verdict.md`);
- they were measured on Petri-dish photographs of the laboratory's archive;
- the app photographs soil on an A4 sheet, and that shift is unmeasured.

Quoting them to a user who captures on paper would state a number nobody has
measured for that user.

**Google sign-in ships.** This stays in the spec and is not promoted: any
later release can hide it again, so it is not hard to reverse. Its
consequences:

- the OAuth client for the distributed build (#275), dropping the unused Drive
  scope (#274), account deletion in the app and on the web (#278), and the
  google_sign_in 7.x migration (#119) are required before submission;
- the Data safety form (#293) declares the name and e-mail.

**The Android application id is `com.visiosoil.app`, applied now.** Play never
lets an id change after the first upload, so it changes before one.

- The namespace moves with it. `MainActivity`'s package, the generated `R`
  class and the manifest's relative `.MainActivity` then keep agreeing, and
  `AndroidManifest.xml` needs no edit.
- The CI `smoke` job launches and finds the process by the new id.
- The template's `TODO` comment above the id goes.

Promotion: #266's decision passes the three tests.
- It is hard to reverse, because a first release's listing and its ratings are
  permanent history.
- It is surprising without context, since shipping a notebook first is the
  obvious alternative.
- A real alternative was rejected.

The id is hard to reverse but not surprising, so it stays in this spec.

## Alternatives Considered

- **Ship a georeferenced field notebook first** (#266). Rejected by the
  Developer on 2026-09-29. It would have shipped sooner, independent of the
  A4-sheet reader, with the UI promising no result and the tips hidden.
- **Quote E0's accuracy with a caveat** in the listing. Rejected: the caveat
  would be doing the work of a measurement that does not exist.
- **Hide sign-in until sync consumes it** (#273). Rejected by the Developer on
  2026-09-29. It would have taken #275, #274, #278 and #119 off the path to
  submission.
- **Keep `com.visiosoil.visiosoil_app`** (#267). Rejected by the Developer on
  2026-09-29. It was valid, and it cost nothing to change.

## Scope

- Includes:
  - `docs/adr/0026-*.md`, promoted from the first decision above, and its
    README decision row.
  - `android/app/build.gradle.kts`: `namespace` and `applicationId` become
    `com.visiosoil.app`, and the template `TODO` goes.
  - `MainActivity.kt` moves to `android/app/src/main/kotlin/com/visiosoil/app/`
    with that package.
  - The CI `smoke` job's `monkey -p` and `pidof` use the new id.
    `test/android_proguard_rules_test.dart`'s pinned string follows.
  - `test/android_application_id_test.dart`, pinning the id, the package and
    the smoke job.
  - The implementation map's A6 Dart (2) entry notes that the A4-sheet reader is
    now the Play release's critical path.
  - After merge, #266, #273 and #267 close with a pointer here.
- Does NOT include:
  - `AndroidManifest.xml`, `ios/Runner/Info.plist`, `test/android_config_test.dart`
    and `test/ios_config_test.dart`. #299 (SPEC 0087) changes them.
  - The iOS bundle id, `com.visiosoil.visiosoilApp`. The Play release is
    Android, and nobody has decided the iOS one.
  - The desktop targets' ids (Linux `APPLICATION_ID`), which ship nowhere.
  - The sign-in work itself (#275, #274, #278, #119), the in-app copy and
    onboarding (#281, #282), and the listing (#294). Each follows ADR 0026 in its
    own change.
  - The A4-sheet reader.

## Acceptance Criteria

- `the_android_application_id_is_com_visiosoil_app`: `build.gradle.kts`
  declares `applicationId` and `namespace` as `com.visiosoil.app`, and the
  template `TODO` is gone.
- `main_activity_is_in_the_application_package`: `MainActivity.kt` exists under
  `kotlin/com/visiosoil/app/` with `package com.visiosoil.app`, and no file is
  left under the old package path.
- `the_smoke_job_launches_the_final_id`: the CI `smoke` job launches and finds
  `com.visiosoil.app`, and no workflow names the old id.
- `the_release_apk_builds_and_boots_under_the_new_id`: on the pull request, CI
  `build` (with its R8 check) and `smoke` pass.
- ADR 0026 exists, records the listing rule, and is indexed by the README, as
  `readme_adr_index_test.dart` checks.

## Reproducibility

```sh
flutter test test/android_application_id_test.dart test/android_proguard_rules_test.dart test/standards
flutter build apk --release
mf check
```

Flutter 3.44.1. CI's `smoke` job boots the release APK under the new id.

## Risks and Assumptions

- **Assumption: nobody has the app installed under the old id beyond
  development.** A build under the new id installs as a separate app, and no
  user data migrates. No release exists, so nothing is lost.
- **Risk: a merge race with #299.** Both touch Android files, but never the
  same ones, so whichever merges second rebases without conflict.
- **What would invalidate this spec:** the Developer revisiting #266 before the
  reader lands. ADR 0026 would then be superseded, and #281, #282 and #294
  would follow the new record.
