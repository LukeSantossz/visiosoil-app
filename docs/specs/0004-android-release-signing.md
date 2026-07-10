# SPEC: build(android): configure release signing from an untracked keystore

## Problem

Release builds are signed with the debug keystore
(`android/app/build.gradle.kts` release block →
`signingConfigs.getByName("debug")`), so distributed APKs can be trivially
resigned or repackaged and no real signing key exists for a distribution channel.

## Design Decision

Add a `signingConfigs.release` block to `android/app/build.gradle.kts` that reads
credentials from an untracked `android/key.properties` file (`storeFile`,
`storePassword`, `keyAlias`, `keyPassword`), and point the release build type at
it. When `key.properties` is absent, fall back to the debug signing config and
log a build-time warning, so contributors and CI can still build a release APK
without any secret. No secret material enters the repository — `.gitignore`
already excludes `*.jks`, `*.keystore`, `key.properties`, and `local.properties`.
Generating and safekeeping the keystore is the maintainer's action (documented in
the README); this change is only the Gradle wiring plus documentation.

## Alternatives Considered

1. Fail the release build when `key.properties` is missing — REJECTED: it would
   break the CI release-build job (which has no keystore) and block any
   contributor from producing a release APK locally; the audit and Flutter's
   documented setup both keep an unsigned/debug fallback.
2. Commit an encrypted keystore or inject via CI secrets only — REJECTED for this
   issue: CI-side signing is #28's scope; this issue is the app-side Gradle
   configuration it depends on, and no secret should live in the repo.

## Scope

- Includes:
  - `signingConfigs.release` in `android/app/build.gradle.kts` sourced from
    `android/key.properties`, with a debug fallback + warning when absent.
  - README "Getting Started" documentation: how to generate the keystore
    (`keytool`) and the `key.properties` format.
  - A config test asserting the release signing wiring and the `.gitignore`
    exclusions (`test/android_signing_test.dart`).
- Does NOT include:
  - Generating or committing any keystore, password, or `key.properties`
    (maintainer action).
  - CI-side signing/secret injection (#28).
  - iOS signing.

## Acceptance Criteria

- `release_build_type_uses_release_signing_config_when_available`:
  `build.gradle.kts` selects a `release` signing config sourced from
  `key.properties` for the release build type (not hardcoded debug).
- `release_build_falls_back_to_debug_without_key_properties`:
  `flutter build apk --release` still succeeds with no `key.properties` present
  (debug fallback), keeping CI green without secrets.
- `no_secret_material_is_tracked`: `.gitignore` excludes `key.properties`,
  `*.jks`, `*.keystore`; no keystore or password is committed.
- `readme_documents_keystore_setup`: the README explains keystore generation and
  the `key.properties` format.

## Reproducibility

`flutter test test/android_signing_test.dart`; `flutter analyze`; `flutter build
apk --release` (with and without `android/key.properties`). With a real keystore,
`apksigner verify --print-certs <apk>` shows the release certificate. Toolchain
Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: contributors and CI build release APKs without the keystore; the
  debug fallback preserves that. A signed release requires the maintainer to
  place `android/key.properties` and the keystore locally.
- Risk: a misconfigured `key.properties` (wrong path/password) fails the release
  build with a Gradle signing error; this is loud and local, not a silent
  mis-sign. The fallback triggers only when the file is absent, not when it is
  present but invalid, so a real signing misconfiguration is surfaced rather than
  masked.
