# Flutter toolchain version: pin a single source of truth and align CI to local

CI and local development are pinned to the same Flutter version — **3.44.1** (Dart
3.12.1). `.github/workflows/ci.yml` sets `flutter-version: "3.44.1"` in the analyze,
test, and build jobs, `pubspec.lock` is committed as resolved on that version, and the
required version is documented in the README Getting Started prerequisites and in
`CLAUDE.md`.

## Status

Accepted. Implemented under issue #100 (SPEC approved at the Spec Gate). Direction (a)
of the SPEC: bump CI to the version contributors already run.

### Decided
- **Single version, 3.44.1** — CI was on 3.38.5 while contributors ran 3.44.1, so the
  newer SDK-pinned transitive packages (`test`, `material_color_utilities`, `meta`,
  `matcher`, `characters`, …) drifted and `flutter pub get` rewrote `pubspec.lock` on
  every local run. One pinned version removes the drift.
- **Align CI up to local, not local down to CI** — bump CI to 3.44.1 rather than force
  contributors onto an older SDK; the version they already run becomes the standard.
- **Lock committed on the chosen version** — regenerated once on 3.44.1 so `pub get`
  leaves the tree clean on that version.
- **Documented, CI-consumed source of truth** — `ci.yml` carries 3.44.1 and the
  README/`CLAUDE.md` name it; a single machine-readable file consumed by both sides is a
  deferred follow-up (see Considered Options (c)).

## Considered Options
- **(b) Pin local to 3.38.5 via a committed `.fvmrc`/`.flutter-version`** — rejected:
  keeps the known-green CI but forces every contributor onto an older SDK through fvm, a
  downgrade from what they already run.
- **(c) A committed version file consumed by both (fvm action / `flutter-version-file`)**
  — rejected as the primary step: mechanically the cleanest single source, but depends on
  an unverified `subosito/flutter-action` capability; deferred as a follow-up now that the
  version itself is aligned.
- **Do nothing / keep reverting the lock by hand** — rejected: the drift recurs on the
  next local `pub get`; a standing tax rather than a one-off.

## Consequences
- Local `flutter pub get` on 3.44.1 leaves `pubspec.lock` unchanged; the working tree is
  no longer perpetually dirty and stays in sync with CI.
- CI runs on the newer SDK-pinned packages; the analyze/test/build jobs are the standing
  verification that 3.44.1 stays green.
- The pinned version is duplicated between `ci.yml` and the docs (not yet single-sourced
  in one machine-readable file); option (c) remains the follow-up to remove that
  duplication.
- Bumping the Flutter version later is a deliberate, reviewable change to the same pin,
  not an ambient drift.
