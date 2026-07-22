# SPEC: build: raise the Dart SDK floor to 3.11

## Problem
`pubspec.yaml` admits Dart 3.10.x (`sdk: ^3.10.4`), which is vulnerable to
CVE-2026-27704 (a `pub get`-time pub-cache symlink path traversal fixed in Dart
3.11.0), a build-time/supply-chain exposure on developer and CI machines.

## Scope
- Includes:
  - Set `environment.sdk` to `^3.11.0` in `pubspec.yaml`.
  - Regenerate `pubspec.lock` on the pinned toolchain (Flutter 3.44.1 / Dart
    3.12.1) so only the environment stanza changes.
- Does NOT include:
  - Raising the floor to the pinned `^3.12.1` (kept at the security boundary, not
    the convenience pin, per ADR 0004's constraint-floor vs pinned-toolchain
    separation).
  - Any dependency version bump, or code using 3.11-only language features.
  - Touching CI (already on 3.44.1/3.12.1, so the floor raise is a no-op there).

## Acceptance Criteria
- `pubspec.yaml` declares `sdk: ^3.11.0`.
- `flutter pub get` on 3.44.1 regenerates `pubspec.lock` with only the
  environment/SDK constraint changed and the tree otherwise clean.
- `flutter analyze` and `flutter test` stay green; the release build stays green
  on CI.
