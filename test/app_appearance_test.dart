// The app starts in the stored theme and keeps the status-bar icons readable
// on it (SPEC 0107, SPEC 0184). Vibration and reduce motion are restored
// before first frame (redesign v11 §3.11).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/main.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';

class _MemoryStore implements AppearanceStore {
  _MemoryStore({this.base = ThemeMode.system, this.sun = false});

  ThemeMode base;
  bool sun;

  @override
  Future<ThemeMode> readBaseThemeMode() async => base;

  @override
  Future<void> writeBaseThemeMode(ThemeMode mode) async => base = mode;

  @override
  Future<bool> readSunMode() async => sun;

  @override
  Future<void> writeSunMode(bool on) async => sun = on;

  bool vibration = true;

  @override
  Future<bool> readVibration() async => vibration;

  @override
  Future<void> writeVibration(bool on) async => vibration = on;

  bool reduceMotion = false;

  @override
  Future<bool> readReduceMotion() async => reduceMotion;

  @override
  Future<void> writeReduceMotion(bool on) async => reduceMotion = on;
}

class _RecordingSync implements NightModeSync {
  @override
  Future<void> apply(ThemeMode mode) async {}
}

Widget _app(
  ThemeMode base,
  void Function(BuildContext) onBuild, {
  bool sun = false,
  bool vibration = true,
  bool reduceMotion = false,
}) =>
    ProviderScope(
      overrides: [
        initialBaseThemeModeProvider.overrideWithValue(base),
        initialSunModeProvider.overrideWithValue(sun),
        initialVibrationProvider.overrideWithValue(vibration),
        initialReduceMotionProvider.overrideWithValue(reduceMotion),
        appearanceStoreProvider
            .overrideWithValue(_MemoryStore(base: base, sun: sun)),
        nightModeSyncProvider.overrideWithValue(_RecordingSync()),
      ],
      child: _AppWithControllersInitialized(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: Builder(builder: (context) {
              onBuild(context);
              return const SizedBox();
            })),
          ),
        ]),
        onBuild: onBuild,
      ),
    );

/// Wraps [VisioSoilApp] and reads the vibration/reduce-motion providers to
/// trigger their controllers to build and set the static flags.
class _AppWithControllersInitialized extends ConsumerWidget {
  const _AppWithControllersInitialized({
    required this.routerConfig,
    required this.onBuild,
  });

  final GoRouter routerConfig;
  final void Function(BuildContext) onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(vibrationProvider);
    ref.watch(reduceMotionProvider);
    return VisioSoilApp(routerConfig: routerConfig);
  }
}

void main() {
  testWidgets('the_first_frame_is_in_the_stored_theme', (tester) async {
    final seen = <Brightness>[];
    await tester.pumpWidget(
      _app(ThemeMode.dark, (context) => seen.add(Theme.of(context).brightness)),
    );

    expect(seen, isNotEmpty);
    expect(seen.first, Brightness.dark);
  });

  // No explicit choice ever made: the first boot follows the system, which
  // the test view reports as light (redesign v11 §2, SPEC 0184).
  testWidgets('first_boot_with_no_stored_choice_follows_the_system',
      (tester) async {
    final seen = <Brightness>[];
    await tester.pumpWidget(
      _app(ThemeMode.system, (context) => seen.add(Theme.of(context).brightness)),
    );

    expect(seen.first, Brightness.light);
  });

  // The same, with the platform reporting dark: a fresh install must not
  // default to light regardless of the device's own brightness.
  testWidgets('dark_first_boot_with_no_stored_choice_follows_the_system',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final seen = <Brightness>[];

    await tester.pumpWidget(
      _app(ThemeMode.system, (context) => seen.add(Theme.of(context).brightness)),
    );

    expect(seen.first, Brightness.dark);
  });

  // With no explicit choice, the app keeps following the system live, not
  // just at the first frame (redesign v11 §2).
  testWidgets('live_light_to_dark_system_change_before_any_choice',
      (tester) async {
    final seen = <Brightness>[];
    await tester.pumpWidget(
      _app(ThemeMode.system, (context) => seen.add(Theme.of(context).brightness)),
    );
    expect(seen.last, Brightness.light);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    // MaterialApp animates a theme change (AnimatedTheme): a single
    // zero-duration pump leaves it mid-transition, still reporting the old
    // brightness.
    await tester.pumpAndSettle();

    expect(seen.last, Brightness.dark);
  });

  // Sol is reached only by an explicit choice; it is never where a fresh
  // install or a plain light/dark base lands (SPEC 0184).
  testWidgets('sol_never_turns_on_by_itself', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(_app(
      ThemeMode.system,
      (context) => seen.add(context.palette.isSun),
    ));
    expect(seen.first, isFalse);

    await tester.pumpWidget(const SizedBox());
    seen.clear();
    await tester.pumpWidget(_app(
      ThemeMode.dark,
      (context) => seen.add(context.palette.isSun),
    ));
    expect(seen.first, isFalse);
  });

  // Sol forces its own light theme and ignores the platform's brightness, and
  // the base underneath it (redesign v11 §2).
  testWidgets('sol_ignores_the_platform_brightness_and_the_base',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final seen = <(Brightness, bool)>[];

    await tester.pumpWidget(_app(
      ThemeMode.dark,
      (context) =>
          seen.add((Theme.of(context).brightness, context.palette.isSun)),
      sun: true,
    ));

    expect(seen.first, (Brightness.light, true));
  });

  testWidgets('status_bar_icons_follow_the_theme', (tester) async {
    SystemUiOverlayStyle overlay() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byWidgetPredicate(
            (w) => w is AnnotatedRegion<SystemUiOverlayStyle>,
          ).first,
        )
        .value;

    await tester.pumpWidget(_app(ThemeMode.dark, (_) {}));
    expect(overlay().statusBarIconBrightness, Brightness.light);
    expect(overlay().statusBarBrightness, Brightness.dark);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ThemeMode.light, (_) {}));
    expect(overlay().statusBarIconBrightness, Brightness.dark);
    expect(overlay().statusBarBrightness, Brightness.light);
  });

  // The platform's own high-contrast accessibility signal turns high
  // contrast on through `highContrastTheme`/`highContrastDarkTheme`
  // (SPEC 0130) — independent of Modo Sol and of any manual switch.
  testWidgets('platform_signal_is_honoured', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final seen = <bool>[];

    await tester.pumpWidget(
      _app(ThemeMode.light,
          (context) => seen.add(context.palette.highContrast)),
    );

    expect(seen.last, isTrue);
  });

  // Sol is its own fixed high-contrast theme (redesign v11 §2), so the
  // platform's own high-contrast signal must not swap it for the legacy
  // high-contrast pair (SPEC 0130) at startup.
  testWidgets('sol_overrides_platform_high_contrast_at_startup',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final seen = <bool>[];

    await tester.pumpWidget(_app(
      ThemeMode.system,
      (context) => seen.add(context.palette.isSun),
      sun: true,
    ));

    expect(seen.last, isTrue);
  });

  // Toggling the platform's high-contrast signal while Sol is already chosen
  // must not knock the app out of Sol (SPEC 0182, SPEC 0184).
  testWidgets('sol_overrides_platform_high_contrast_when_toggled_during_use',
      (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(_app(
      ThemeMode.system,
      (context) => seen.add(context.palette.isSun),
      sun: true,
    ));
    expect(seen.last, isTrue);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    expect(seen.last, isTrue);
  });

  // Vibration is restored before the first frame: off persists across restart
  // (redesign v11 §3.11 acceptance criterion).
  testWidgets('vibration_off_survives_a_restart', (tester) async {
    AppHaptics.enabled = true;
    await tester.pumpWidget(_app(
      ThemeMode.light,
      (_) {},
      vibration: false,
    ));
    await tester.pumpAndSettle();

    expect(AppHaptics.enabled, isFalse);
  });

  // Reduce motion is restored before the first frame (redesign v11 §3.11).
  testWidgets('reduce_motion_survives_a_restart', (tester) async {
    AppMotion.reduceMotion = false;
    await tester.pumpWidget(_app(
      ThemeMode.light,
      (_) {},
      reduceMotion: true,
    ));
    await tester.pumpAndSettle();

    expect(AppMotion.reduceMotion, isTrue);
  });
}
