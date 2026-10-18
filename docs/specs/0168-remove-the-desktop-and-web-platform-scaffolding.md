# SPEC: chore: remove the desktop and web platform scaffolding

## Problem

The repository tracks Flutter's template scaffolding for macOS, Linux, Windows and web (56 files, flagged by the nightly audits #393 and #396), although the app targets Android and iOS only, nothing builds, tests or deploys the other four, and `.metadata` still lists all seven platform entries as if each were a target.

## Scope

- Includes:
  - Deleting the tracked files under `macos/`, `linux/`, `windows/` and `web/`.
  - `.metadata`: the `linux`, `macos`, `web` and `windows` entries under `migration.platforms`, leaving `root`, `android` and `ios`.
  - `pubspec.yaml`: the template's two-line comment on how Windows reads `build-name`, which describes a platform that is no longer there.
  - A test that keeps the four platforms out.
- Does NOT include:
  - `pubspec.lock` or any dependency. Plugins keep their desktop and web implementations, and pub resolves them whatever platform directories exist. The lock must come out of `flutter pub get` unchanged.
  - `site/`, the GitHub Pages content, which is not Flutter web and is published by `pages.yml`.
  - Comments and tests that name Windows, macOS or Linux as the developer's or CI's host OS, such as the CRLF note in `site_pages_test.dart` or the `storeFile` slash advice in the README.
  - `android/` and `ios/`.
  - Closing the audit PRs #393 to #397, which the Developer decides separately.

## Acceptance Criteria

- `only_the_mobile_platforms_are_scaffolded`: no file tracked by git lives under `macos/`, `linux/`, `windows/` or `web/`, and `.metadata`'s `migration.platforms` lists exactly `root`, `android` and `ios`.
- `the_lock_is_unchanged`: `flutter pub get` leaves `pubspec.lock` byte-identical.
- `the_mobile_builds_still_pass`: `flutter analyze` and `flutter test` pass locally, and CI's `build`, `build-ios` and `smoke` jobs pass on the PR.
