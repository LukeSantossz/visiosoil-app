# SPEC: feat(android): show the app mark on the native launch screen

## Problem

Before Flutter draws its first frame, Android shows the template's launch
window: plain white on Android 11 and earlier, the system's default background
around the launcher icon on Android 12 and later, and black on either when the
phone is in dark mode, while the app itself is light-only. The Dart splash then
fades its logo in from transparent, so the mark is either absent or disappears
and comes back (#288).

## Design Decision

The launch reads as one screen: the native window shows the Dart splash's logo
tile at the same place and size, and the Dart splash's first frame shows that
tile already in place, so nothing about the mark changes when Flutter takes
over.

- **One tile, drawn natively.** The tile is two drawables:
  - `launch_tile.xml`, a rounded rectangle with the `primary` to `tertiary`
    gradient the Dart splash paints;
  - `launch_mark.xml`, a vector drawable of the brand mark in white.

  The vector is drawn from the same geometry `paintVisioSoilMark` uses. That
  geometry moves into one constant, which both the painter and a test read, so
  the two cannot drift.
- **Android 11 and earlier.** `launch_background.xml` layers the app background
  (`AppColors.background`), then the 120 dp tile, then the 64 dp mark, centred.
- **Android 12 and later.** `values-v31/styles.xml` sets
  `windowSplashScreenBackground` to the app background, and
  `windowSplashScreenAnimatedIcon` to `launch_icon.xml`. That drawable is the
  same tile and mark centred on the platform's 288 dp icon canvas, which the
  system masks to a 192 dp circle. The tile's corners lie 85 dp from its centre,
  so the mask never cuts them.
- **Both modes are light.** The launch window and `NormalTheme` paint the app
  background in light and dark system modes, because the app has no dark theme
  on `main` (`MaterialApp` sets only `AppTheme.light`). The template's dark-mode
  styles are removed.
- **The Dart splash keeps the tile still.** The tile is centred in the full
  view rather than in a `SafeArea` column, at full opacity and full size from
  the first frame. Only what the native window cannot show animates in:
  - the name, the tagline and the status line fade in below the tile;
  - the tile's shadow fades in with them.

  The tile's size, mark size and corner radius become named constants that the
  native test reads.

## Alternatives Considered

1. **`flutter_native_splash`**, generating the resources from YAML, as
   `flutter_launcher_icons` does for the icon. Rejected: it rasterises the
   image into PNGs for every density and rewrites the iOS storyboard by default.
   It cannot see the Dart splash, so matching its tile would still be done by
   hand.
2. **Leave the Android 12+ system icon as it is**, the launcher icon in its
   circle. Rejected: the first Flutter frame shows a rounded square at a
   different size, so the mark would visibly change shape at the hand-over.
   That is the jump this change removes.
3. **Follow the system's dark mode with a dark launch background.** Rejected on
   `main`: Flutter always paints light, so a dark launch window is itself a
   flash at the first frame. When an app-level dark theme lands, a night variant
   returns with it (#245).
4. **Keep the Dart splash's fade and scale, and start them from the native
   state.** Rejected: an animation that starts at the final state does not
   animate. The fade is kept where it adds something: on the text, which the
   native window does not show.

## Scope

- Includes:
  - `res/values/colors.xml`: the launch background colour and the tile's two
    gradient colours.
  - `res/drawable/launch_tile.xml`, `res/drawable/launch_mark.xml` and
    `res/drawable/launch_icon.xml`, new.
  - `res/drawable/launch_background.xml`, rewritten.
    `res/drawable-v21/launch_background.xml` is deleted: with `minSdk` 24 it
    always shadowed the unqualified file, which was dead.
  - `res/values/styles.xml`: `NormalTheme` paints the app background.
  - `res/values-v31/styles.xml`, new. `res/values-night/styles.xml`, deleted.
  - `lib/core/widgets/visio_soil_logo.dart`: the mark's geometry as one
    constant, which `paintVisioSoilMark` reads. What it paints does not change.
  - `lib/core/features/splash/splash_screen.dart`: the layout and animation
    above, and the tile constants.
  - `test/android_launch_screen_test.dart` and
    `test/features/splash/splash_screen_test.dart`, new.
- Does NOT include:
  - What the Dart splash does: the permission requests (#286) and the route it
    takes afterwards.
  - An app-level dark theme, and the launch following the app's stored
    brightness (#245).
  - iOS's `LaunchScreen.storyboard`.
  - The launcher icon, which keeps its full-bleed green square and circle mask.
  - An animated Android 12 icon, or a branding image under it.

## Acceptance Criteria

- `launch_colours_are_the_splash_colours`: in `res/values/colors.xml`, the
  launch background equals `AppColors.background`, and the tile's gradient runs
  from `AppColors.primary` to `AppColors.tertiary`.
- `launch_tile_matches_the_splash_tile`: `launch_tile.xml` has the splash
  tile's corner radius, and its gradient runs from top-left to bottom-right.
  Both `launch_background.xml` and `launch_icon.xml` draw it at the splash
  tile's size, and draw the mark at the splash mark's size.
- `launch_mark_draws_the_painted_mark`: `launch_mark.xml` draws exactly the
  ring, three grains and handle of the mark geometry, in white, on its 48-unit
  viewport.
- `pre_android_12_launch_window_draws_the_tile_on_the_app_background`:
  `launch_background.xml` layers the background, the tile and the mark in that
  order, centred, and it is the only `launch_background` drawable in `res/`.
- `android_12_splash_shows_the_same_tile`: `LaunchTheme` in
  `res/values-v31/styles.xml` sets `windowSplashScreenBackground` to the launch
  background and `windowSplashScreenAnimatedIcon` to `launch_icon.xml`, whose
  canvas is 288 dp.
- `no_window_paints_the_template_background`: `NormalTheme` paints the launch
  background, and no styles file under `res/` names `Theme.Black` or
  `?android:colorBackground`.
- `splash_first_frame_shows_the_tile_in_place`: on the splash's first frame,
  the tile is at full size, centred in the view, casts no shadow, and has no
  opacity below one between it and the screen, while the name is still
  transparent.
- `splash_tile_holds_still_through_the_reveal`: after the reveal completes, the
  tile occupies exactly the rectangle it had on the first frame, and it casts
  the brand shadow.

## Reproducibility

`flutter test test/android_launch_screen_test.dart
test/features/splash/splash_screen_test.dart` for the criteria.

For the device check, run a cold launch of the release APK:

1. `adb shell am force-stop <package>`
2. `adb shell am start -W -n <package>/.MainActivity`
3. Record it with `adb shell screenrecord`, and extract frames with `ffmpeg`.

Do this on the local API 36 emulator in light and dark mode, and on an API 30
emulator (`system-images;android-30;google_apis;x86_64`). The mark's bounding
box is measured in the last native frame and in the first Flutter frame.
Flutter 3.44.1, compile and target SDK 36.

## Risks and Assumptions

- Assumes the native window and the Flutter view share a centre. That holds
  where Flutter draws edge to edge, which is every Android 15+ device, since the
  app targets 35+. On Android 14 and earlier, Flutter does not draw behind the
  navigation bar. So its centre may sit higher than the window's, by half that
  bar. The API 30 recording measures the offset, and the pull request reports
  it.
- Assumes Android 12+ shows `windowSplashScreenAnimatedIcon` unscaled on its
  288 dp canvas, which is the documented size for an icon without a
  background.
- If an app-level dark theme lands before this merges, the light-only premise is
  wrong and the night variant has to come back in this change.
- SPEC 0088 is held by another open change. This spec merges after it.
