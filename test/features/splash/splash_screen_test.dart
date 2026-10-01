import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/splash/splash_screen.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

/// Guards the Dart side of the launch hand-over (#288, SPEC 0089): the tile the
/// native launch window draws is already in place, whole and still, on the
/// splash's first frame, and only what the native window cannot show animates
/// in.
void main() {
  Future<void> pumpSplash(WidgetTester tester) => tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SplashScreen())),
      );

  // The splash schedules its permission requests 1.2 s after it mounts.
  // Unmounting first makes that callback stop at its `mounted` check, and
  // advancing the clock lets it run, so no timer outlives the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  Finder tile() => find
      .ancestor(
        of: find.byType(VisioSoilLogo),
        matching: find.byType(Container),
      )
      .first;

  /// Where the native window draws the tile: centred in the view.
  Rect nativeTile(WidgetTester tester) {
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    return Rect.fromCenter(
      center: Offset(view.width / 2, view.height / 2),
      width: SplashScreen.logoTileSize,
      height: SplashScreen.logoTileSize,
    );
  }

  List<BoxShadow> shadows(WidgetTester tester) =>
      (tester.widget<Container>(tile()).decoration! as BoxDecoration)
          .boxShadow ??
      const [];

  testWidgets('splash_first_frame_shows_the_tile_in_place', (tester) async {
    await pumpSplash(tester);

    // getRect goes through every paint transform, so a scale shows here too.
    expect(tester.getRect(tile()), nativeTile(tester));
    expect(
      shadows(tester).every((shadow) => shadow.color.a == 0),
      isTrue,
      reason: 'the native window draws no shadow',
    );
    for (final opacity in tester.widgetList<Opacity>(
      find.ancestor(of: tile(), matching: find.byType(Opacity)),
    )) {
      expect(opacity.opacity, 1);
    }
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: tile(), matching: find.byType(FadeTransition)),
    )) {
      expect(fade.opacity.value, 1);
    }

    final nameFade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('VisioSoil'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(nameFade.opacity.value, 0);

    await unmount(tester);
  });

  testWidgets('splash_tile_holds_still_through_the_reveal', (tester) async {
    await pumpSplash(tester);
    final first = tester.getRect(tile());

    await tester.pump(AppMotion.reveal ~/ 2);
    expect(tester.getRect(tile()), first);

    await tester.pump(AppMotion.reveal);
    expect(tester.getRect(tile()), first);
    expect(
      shadows(tester).map((shadow) => shadow.color),
      contains(AppColors.shadowBrand),
    );

    await unmount(tester);
  });
}
