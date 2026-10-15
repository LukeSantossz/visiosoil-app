# SPEC: feat(settings): link the privacy policy from the settings screen

## Problem

Google Play expects the privacy policy to be reachable from inside the app, and
Settings has no link to it (#279). SPEC 0156 publishes the policy at a stable
URL.

## Design Decision

**Settings gains a "Política de privacidade" tile under SOBRE, below "Versão do
app". Tapping it opens the policy's URL in the external browser through
`url_launcher`.**

- **The URL is one constant**, `AppLinks.privacyPolicy`, in a new
  `lib/core/constants/app_links.dart`:
  `https://lukesantossz.github.io/visiosoil-app/privacidade.html`. It is not a
  UI string, so it does not join `AppStrings`.
- **The tile** reuses the screen's `_SettingsTile`, with
  `Icons.privacy_tip_outlined` and the trailing arrow the "Como capturar bem"
  tile uses.
- **The launch** is `launchUrl(uri, mode: LaunchMode.externalApplication)`. The
  browser shows the page with its own address bar, which a reader of a policy
  should see.
- **A failure is said, not swallowed.** If `launchUrl` returns `false`, or
  throws a `PlatformException` or a `MissingPluginException`, a snackbar reads
  "Não foi possível abrir a política de privacidade." The cause is logged through `dart:developer`, as the account
  tile logs a failed connectivity read.
- **Android 11 and later need a `<queries>` entry** for an `https` `VIEW` intent
  so the launcher can resolve a browser. It joins the existing `PROCESS_TEXT`
  entry in `AndroidManifest.xml`. iOS needs no entry for `https`.
- **`url_launcher` is a new dependency.** It is the Flutter team's plugin, and
  #279 names it. Its Linux, web and Windows packages and its platform interface
  are already in the lock file through `share_plus`; it adds `url_launcher`,
  `url_launcher_android`, `url_launcher_ios` and `url_launcher_macos`.
- **Tests replace `UrlLauncherPlatform.instance`** with a fake, the plugin's
  documented test seam. The fake extends the platform class, as the share tests'
  `RecordingSharePlatform` does, so it needs only
  `url_launcher_platform_interface` as a dev dependency; it is already in the
  lock file.

## Alternatives Considered

- **A service seam with a provider, as `ShareService` wraps `share_plus`.**
  Rejected. One call site with one URL does not need a production abstraction;
  the plugin's own platform seam tests it without one.
- **An in-app WebView.** Rejected. It adds a heavier plugin, and it hides the
  address the reader should see.
- **Copy the URL, or share it.** Rejected. Play expects the policy to open from
  the app, and a copied link is one step the user may not take.

## Scope

- Includes:
  - `lib/core/constants/app_links.dart` with `AppLinks.privacyPolicy`.
  - `lib/core/features/settings/settings_screen.dart`: the tile, the launch and
    the failure snackbar.
  - `android/app/src/main/AndroidManifest.xml`: the `https` `VIEW` query.
  - `pubspec.yaml` and `pubspec.lock`: `url_launcher`, and the dev
    dependency.
  - Tests in `test/features/settings/settings_screen_test.dart`, and a manifest
    assertion beside the existing ones in `test/android_config_test.dart`.
- Does NOT include:
  - The policy or the deletion page (SPEC 0156).
  - A link to the deletion page in the app. "Excluir conta" is the in-app path.
  - Links anywhere else, such as onboarding or sign-in.
  - Any other change to Settings.

## Acceptance Criteria

- `settings_lists_the_privacy_policy_under_sobre`: the tile "Política de
  privacidade" shows between "Versão do app" and the AJUDA header.
- `tapping_the_privacy_policy_opens_it_in_the_browser`: a tap launches exactly
  `AppLinks.privacyPolicy`, once, in external-application mode.
- `privacy_policy_url_is_the_published_page`: `AppLinks.privacyPolicy` equals
  `https://lukesantossz.github.io/visiosoil-app/privacidade.html`.
- `a_launch_that_fails_says_so`: when the launcher returns `false`, and when it
  throws a `PlatformException`, the snackbar shows and the screen stays.
- `manifest_queries_an_https_view_intent`: the manifest's `<queries>` holds a
  `VIEW` intent with the `https` scheme.
- `flutter analyze`, the full suite and `mf check` pass.

## Reproducibility

```sh
flutter test test/features/settings/settings_screen_test.dart \
  test/android_config_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: the URL is live before a build ships with it.** SPEC 0156's
  deploy serves it; this merges after 0156, and the PR records the URL
  answering.
- **Risk: a phone with no browser.** The launch returns `false` and the user
  reads the snackbar, not silence.
- **Merge order:** 0157 merges after 0156, since `main`'s contiguity check
  fails on a gap.
