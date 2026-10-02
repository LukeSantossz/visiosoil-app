# SPEC: fix(android): draw edge to edge on Android 12 to 14 so the launch stays still

## Problem

On Android 12 to 14 the launch jumps when Flutter takes over from the system splash (#304, found by SPEC 0089's device check):

| | System splash | Flutter splash |
| --- | --- | --- |
| Area drawn | the whole display, app background under both bars | stops above the navigation bar |
| Status bar | app background | grey scrim |
| Navigation bar | app background | black, 48 dp with three buttons, 24 dp with gestures |
| Tile centre | display centre | 11 dp higher with gestures, about 23 dp with three buttons |

Two neighbouring versions are already continuous:
- **Android 15+** enforces edge to edge for targetSdk 35+, so both windows span the display.
- **Android 11 and earlier** inset both windows above the navigation bar.

Only 12 to 14 mix the two: a system splash that spans the display, and a Flutter view that does not.

## Design Decision

**On Android 12 to 14, `MainActivity` lays the window out edge to edge, the way Android 15 does.** It does so in `onCreate`, before the Flutter view attaches. On API 31 through 34:
- `window.setDecorFitsSystemWindows(false)`, so the Flutter view spans the display under both bars;
- transparent status and navigation bars;
- status-bar contrast not enforced; navigation-bar contrast enforced, the platform default. The system then keeps its translucent scrim behind a three-button bar and none behind the gesture handle, as on 15+.

Flutter already lays its screens out against the insets it receives, which is how Android 15 runs today.

**The navigation-bar icons follow the theme natively.** The bar is now see-through on 12 to 14, so its icons must read on the app's background:
- dark icons in the light theme;
- light icons in the dark theme.

`MainActivity` sets `APPEARANCE_LIGHT_NAVIGATION_BARS` from the activity's night mode. It sets it at creation and again in `onConfigurationChanged`, which the manifest already routes `uiMode` to. Since SPEC 0107 that night mode is the user's theme choice on API 31+.

Dart does not set it. On Android 11 and earlier the bar stays opaque black, where dark icons would vanish, and Dart cannot tell the versions apart without a new channel.

**Android 11 and earlier and Android 15+ are left as they are.** Both are continuous today, measured in SPEC 0089. Drawing edge to edge on 11 and earlier would move the jump there, unless the launch window also drew under the bars. That window is themed before any app code runs.

## Alternatives Considered

- **`SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` from Dart.** Rejected:
  - It applies on every Android version, so it would move the jump to Android 11 and earlier.
  - Dart cannot gate it by version without a new channel.
  - It runs only after the engine starts.
- **Draw the launch window under the bars on Android 11 and earlier too, and go edge to edge everywhere.** Rejected: it changes a launch that is continuous today, for no user-visible gain, and it adds translucent-bar flags to the pre-12 theme.
- **androidx `enableEdgeToEdge()`.** Rejected: it needs a `ComponentActivity`, and `FlutterActivity` is not one. The platform calls above are what it makes on API 29+.

## Scope

- Includes:
  - `MainActivity.kt`: the API 31–34 window setup and the navigation-bar icon appearance, at creation and on configuration change.
  - A source test that pins both to that API range.
  - The device check below.
- Does NOT include:
  - Any change on Android 11 and earlier, or on Android 15+.
  - The bar colours on screens that set their own, such as the photo viewer.
  - iOS.

## Acceptance Criteria

- `edge_to_edge_only_on_android_12_to_14`: `MainActivity` calls `setDecorFitsSystemWindows(false)` and makes both bars transparent, inside a guard of API 31 to 34, and nowhere else.
- `navigation_icons_follow_the_night_mode`: `MainActivity` sets `APPEARANCE_LIGHT_NAVIGATION_BARS` from the configuration's night mask, both in `onCreate` and in `onConfigurationChanged`, under the same API guard.
- `the_launch_holds_still_on_a_device`: frame sampling of a cold launch, by SPEC 0089's method:
  - **API 34, gestures and three buttons:** the tile's centre moves at most 2 px from the system splash to the Flutter splash, and neither bar changes colour at the hand-over.
  - **API 30 and API 36:** stay as SPEC 0089 measured them.
- `no_content_under_the_navigation_bar`: on API 34, home, history, capture, details, settings and onboarding keep their last control clear of the navigation bar, in both themes.

## Reproducibility

`flutter test test/android_edge_to_edge_test.dart`

Device check: a release APK on the API 30, 34 and 36 emulators. Record the launch with `adb shell screenrecord`, extract the frames with `ffmpeg`, and measure the tile's bounding box with PIL. Switch the navigation mode with `cmd overlay enable-exclusive`.

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumes Flutter's screens already handle the bottom inset, because Android 15+ runs edge to edge today. The device pass checks that on 12 to 14 rather than trusting it.
- The three-button scrim is the platform's, as on 15+, so its exact colour is the system's rather than the app's.
- Android 11 and earlier keep their opaque bars, which SPEC 0089 measured as continuous.
