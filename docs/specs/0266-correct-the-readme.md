# SPEC: docs(readme): correct what the README states about the toolchain, CI and capture

## Problem

On 2026-11-09 the README states five things the repository does not bear out, and its architecture diagram does not render:

- **Prerequisites.** "Another 3.x SDK rewrites `pubspec.lock` and `analysis_options.yaml` on `flutter pub get`." `flutter pub get` rewrites the lockfile only. The `analysis_options.yaml` change seen on this machine is an analyzer `exclude` block added by hand, and no SDK writes it.
- **Camera only.** "Gallery import is not offered, so no photograph is classified without the guided frame (SPEC 0211)." The first half is true. The second is not: when the guided camera is unavailable, capture falls back to the system camera (`GuidedCaptureUnavailable` in `capture_screen.dart`), and that photograph is classified too, with no frame. The README's own What It Does section already says the system camera remains as a fallback.
- **CI in Done.** The line lists what the workflow runs, but not the Kotlin unit tests SPEC 0263 added to the build job (`./gradlew :app:testReleaseUnitTest`).
- **Tests.** The commands do not include those Kotlin tests, so a contributor cannot run locally what CI would run.
- **CI is paused, and the README does not say so.** The `CI` workflow has been disabled on GitHub since 2026-11-08 (`gh workflow disable CI`, at the Developer's request), so no change since then has been checked by CI. The badge and the Done line read as if it ran.
- **Architecture diagram.** GitHub shows "Unable to render rich display" with a lexical error on line 10 of the Mermaid block. The two dotted edges write their labels inline (`-. spec.json .->`), and the dot inside `spec.json` and `corpus.json` breaks the inline label.

## Scope

- Includes:
  - `README.md`:
    - the Prerequisites line names only `pubspec.lock`;
    - the Camera only limitation names the system-camera fallback;
    - the CI line in Done names the Kotlin unit tests;
    - the Tests section gives the Kotlin command, with the release build it needs first;
    - Known Issues & Limitations gains a line saying the workflow is disabled, since when, and what checks a change meanwhile;
    - the Architecture diagram's two dotted edges carry their labels in the quoted pipe form (`-.->|"spec.json"|`), with the same nodes and edges.
  - This spec.
- Does NOT include:
  - any code, asset, test or workflow change;
  - re-enabling CI, or removing or changing the CI badge;
  - anything SPEC 0265 changes in the app. That PR is not merged, and the README describes `main`;
  - `ml/README.md`, `corpus/README.md`, `docs/README.md`, or `docs/agents/project.md` and the files generated from it.

## Acceptance Criteria

- `grep -n "analysis_options" README.md` prints nothing.
- The Camera only line names the system camera as the fallback when the guided camera is unavailable, and no longer says that no photograph is classified without the guided frame.
- `README.md` names `:app:testReleaseUnitTest` in the Tests section, and names the Kotlin unit tests in the CI line under Done.
- Known Issues & Limitations states that the `CI` workflow is disabled on GitHub since 2026-11-08, and names `flutter analyze`, `flutter test` and `mf check` as the local checks meanwhile.
- No dotted edge in the README's Mermaid block uses the inline label form `-. ... .->`; both write the label as `-.->|"..."|`, and GitHub renders the diagram on the branch's README view.
- `grep -nP "[\x{2013}\x{2014}]" README.md` prints nothing (SPEC 0256).
- `flutter test test/standards test/android_signing_test.dart` passes, and `mf check` passes.
