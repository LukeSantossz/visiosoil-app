// The app starts in the stored theme and keeps the status-bar icons readable
// on it (SPEC 0107). Vibration and reduce motion are restored before first frame
// (redesign v11 §3.11).
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
  _MemoryStore(this.stored);

  ThemeMode stored;

  @override
  Future<ThemeMode> read() async => stored;

  @override
  Future<void> write(ThemeMode mode) async => stored = mode;

  bool highContrast = false;

  @override
  Future<bool> readHighContrast() async => highContrast;

  @override
  Future<void> writeHighContrast(bool on) async => highContrast = on;

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
  ThemeMode stored,
  void Function(BuildContext) onBuild, {
  bool highContrast = false,
  bool vibration = true,
  bool reduceMotion = false,
}) =>
    ProviderScope(
      overrides: [
        initialThemeModeProvider.overrideWithValue(stored),
        initialHighContrastProvider.overrideWithValue(highContrast),
        initialVibrationProvider.overrideWithValue(vibration),
        initialReduceMotionProvider.overrideWithValue(reduceMotion),
        appearanceStoreProvider.overrideWithValue(_MemoryStore(stored)),
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

  // High contrast is restored before the first frame, and the platform's own
  // signal turns it on too (SPEC 0130).
  testWidgets('high_contrast_survives_a_restart', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(_app(
      ThemeMode.light,
      (context) => seen.add(context.palette.highContrast),
      highContrast: true,
    ));

    expect(seen.first, isTrue);
  });

  testWidgets('platform_signal_is_honoured', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final seen = <bool>[];

    await tester.pumpWidget(
      _app(ThemeMode.light, (context) => seen.add(context.palette.highContrast)),
    );

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
