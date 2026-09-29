# SPEC: fix(android): show VisioSoil as the app name instead of visiosoil_app

## Problem

The launcher, the recent-apps list, the system settings and every permission
dialog name the app `visiosoil_app`, the Flutter template's placeholder, instead
of VisioSoil (#280).

## Scope

- Includes:
  - `android/app/src/main/AndroidManifest.xml`: `android:label` becomes
    `VisioSoil`. The label is a literal, as it is today, because the app ships
    one language.
  - `ios/Runner/Info.plist`: `CFBundleDisplayName` becomes `VisioSoil`, from
    `Visiosoil App`, so the name is the same on both platforms.
  - `pubspec.yaml`: `description` becomes one sentence about the app, replacing
    the template's "A new Flutter project."
  - `test/android_config_test.dart` and `test/ios_config_test.dart` pin the two
    names, and a test pins the pubspec description.
- Does NOT include:
  - The `applicationId`, the Android `namespace` and the iOS bundle identifier.
    They are identifiers, not names, and choosing the final id is #267.
  - iOS `CFBundleName`, which stays `visiosoil_app`. iOS shows it only where no
    display name is set, and this change sets one.
  - The web, Windows, Linux and macOS runners. None of them is part of the Play
    release, and `web/index.html` and `web/manifest.json` keep the template
    description.
  - The name on the Play listing, which is set in the Play Console (#294), and
    the native launch screen (#288).
  - Moving the label into a string resource for translation.

## Acceptance Criteria

- `android_manifest_labels_the_app_visiosoil`: the `<application>` element of
  `android/app/src/main/AndroidManifest.xml` declares
  `android:label="VisioSoil"`.
- `ios_display_name_is_visiosoil`: `CFBundleDisplayName` in
  `ios/Runner/Info.plist` is `VisioSoil`.
- `pubspec_description_is_not_the_template_default`: the `description` in
  `pubspec.yaml` is non-empty and is not `A new Flutter project.`
