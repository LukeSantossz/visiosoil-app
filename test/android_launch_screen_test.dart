import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/splash/splash_screen.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

/// Guards the native launch screen against the Dart splash it hands over to
/// (#288, SPEC 0089).
///
/// The window Android shows before Flutter's first frame draws the splash's
/// logo tile, in the splash's colours and at the splash's size, so the mark
/// does not change when Flutter takes over. Every number here is read from the
/// Dart side rather than repeated, so a change to the splash fails this test
/// until the drawables follow.
void main() {
  const res = 'android/app/src/main/res';
  String read(String path) => File('$res/$path').readAsStringSync();

  /// The `<item>` elements of a layer list, in drawing order.
  List<String> layers(String layerList) =>
      RegExp(r'<item\b(?:[^>]*/>|.*?</item>)', dotAll: true)
          .allMatches(layerList)
          .map((m) => m.group(0)!)
          .toList();

  String? attribute(String element, String name) =>
      RegExp('android:$name="([^"]*)"').firstMatch(element)?.group(1);

  double dp(String? value) {
    expect(value, matches(RegExp(r'^\d+(\.\d+)?dp$')));
    return double.parse(value!.substring(0, value.length - 2));
  }

  Color colour(String name) {
    final hex = RegExp('<color name="$name">#([0-9A-Fa-f]{6,8})</color>')
        .firstMatch(read('values/colors.xml'))
        ?.group(1);
    expect(hex, isNotNull, reason: '@color/$name is not in values/colors.xml');
    final value = int.parse(hex!, radix: 16);
    return Color(hex.length == 6 ? 0xFF000000 | value : value);
  }

  /// The `<item name="…">` values of [style] in a styles file.
  Map<String, String> style(String stylesFile, String style) {
    final body = RegExp(
      '<style name="$style"[^>]*>(.*?)</style>',
      dotAll: true,
    ).firstMatch(stylesFile)?.group(1);
    expect(body, isNotNull, reason: '$style is not declared');
    return {
      for (final m in RegExp(r'<item name="([^"]+)">([^<]*)</item>')
          .allMatches(body!))
        m.group(1)!: m.group(2)!.trim(),
    };
  }

  /// Asserts [items] draw the tile and then the mark over it, each centred and
  /// at [scale] times the splash's size.
  void expectTileThenMark(List<String> items, String file, {double scale = 1}) {
    final tile = items.indexWhere(
      (i) => attribute(i, 'drawable') == '@drawable/launch_tile',
    );
    final mark = items.indexWhere(
      (i) => attribute(i, 'drawable') == '@drawable/launch_mark',
    );
    expect(tile, isNot(-1), reason: '$file does not draw the tile');
    expect(mark, greaterThan(tile), reason: '$file must draw the mark on top');
    for (final (index, size) in [
      (tile, SplashScreen.logoTileSize),
      (mark, SplashScreen.logoMarkSize),
    ]) {
      expect(attribute(items[index], 'gravity'), 'center', reason: file);
      expect(dp(attribute(items[index], 'width')), size * scale, reason: file);
      expect(dp(attribute(items[index], 'height')), size * scale, reason: file);
    }
  }

  /// The commands of a vector path, and every number in it, in order.
  (String, List<double>) parsePath(String path) {
    final data = attribute(path, 'pathData')!;
    return (
      data.replaceAll(RegExp(r'[^A-Za-z]'), ''),
      RegExp(r'-?\d+(?:\.\d+)?')
          .allMatches(data)
          .map((m) => double.parse(m.group(0)!))
          .toList(),
    );
  }

  void expectNumbers(List<double> actual, List<double> expected) {
    expect(actual, hasLength(expected.length));
    for (var i = 0; i < expected.length; i++) {
      expect(actual[i], closeTo(expected[i], 1e-9));
    }
  }

  test('launch_colours_are_the_splash_colours', () {
    expect(colour('launch_background'), AppColors.background);
    expect(colour('launch_tile_start'), AppColors.primary);
    expect(colour('launch_tile_end'), AppColors.tertiary);
  });

  test('launch_tile_matches_the_splash_tile', () {
    const s = SplashScreen.logoTileSize;
    const r = SplashScreen.logoTileRadius;

    // A vector, so its corners scale with the size it is drawn at.
    final tile = read('drawable/launch_tile.xml');
    for (final side in ['viewportWidth', 'viewportHeight']) {
      expect(double.parse(attribute(tile, side)!), s);
    }

    final path = RegExp(r'<path\b[^>]*>').firstMatch(tile)?.group(0);
    expect(path, isNotNull, reason: 'launch_tile.xml has no <path>');
    final (commands, numbers) = parsePath(path!);
    // The square, clockwise from the end of the top-left corner.
    expect(commands, 'MHAVAHAVAZ');
    expectNumbers(numbers, [
      r, 0, s - r, //
      r, r, 0, 0, 1, s, r, s - r,
      r, r, 0, 0, 1, s - r, s, r,
      r, r, 0, 0, 1, 0, s - r, r,
      r, r, 0, 0, 1, r, 0,
    ]);

    final gradient = RegExp(r'<gradient\b[^>]*>').firstMatch(tile)?.group(0);
    expect(gradient, isNotNull, reason: 'launch_tile.xml has no <gradient>');
    // From the top-left corner to the bottom-right one, as the splash's
    // LinearGradient(topLeft, bottomRight) runs.
    expect(attribute(gradient!, 'type'), 'linear');
    expectNumbers(
      [
        for (final axis in ['startX', 'startY', 'endX', 'endY'])
          double.parse(attribute(gradient, axis)!),
      ],
      [0, 0, s, s],
    );
    expect(attribute(gradient, 'startColor'), '@color/launch_tile_start');
    expect(attribute(gradient, 'endColor'), '@color/launch_tile_end');

    expectTileThenMark(
      layers(read('drawable/launch_background.xml')),
      'launch_background.xml',
    );
    // Android 12+ lays an icon without a background out in 108 dp and shows it
    // at 192 dp, so the icon is drawn smaller to appear at the splash's size.
    expectTileThenMark(
      layers(read('drawable/launch_icon.xml')),
      'launch_icon.xml',
      scale: 108 / 192,
    );
  });

  test('launch_mark_draws_the_painted_mark', () {
    final vector = read('drawable/launch_mark.xml');
    for (final side in ['viewportWidth', 'viewportHeight']) {
      expect(
        double.parse(attribute(vector, side)!),
        VisioSoilMarkGeometry.viewBox,
      );
    }

    final paths = RegExp(r'<path\b[^>]*>')
        .allMatches(vector)
        .map((m) => m.group(0)!)
        .toList();
    expect(paths, hasLength(2 + VisioSoilMarkGeometry.grains.length));

    /// The commands of a path, and every number in it, in order.
    (String, List<double>) parse(String path) {
      final data = attribute(path, 'pathData')!;
      return (
        data.replaceAll(RegExp(r'[^A-Za-z]'), ''),
        RegExp(r'-?\d+(?:\.\d+)?')
            .allMatches(data)
            .map((m) => double.parse(m.group(0)!))
            .toList(),
      );
    }

    // A circle is two half arcs from its leftmost point.
    List<double> circle(Offset centre, double r) =>
        [centre.dx - r, centre.dy, r, r, 0, 1, 0, 2 * r, 0, r, r, 0, 1, 0, -2 * r, 0];

    void expectNumbers(List<double> actual, List<double> expected) {
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(actual[i], closeTo(expected[i], 1e-9));
      }
    }

    const white = '#FFFFFFFF';

    final ring = paths.first;
    final (ringCommands, ringNumbers) = parse(ring);
    expect(ringCommands, 'Maa');
    expectNumbers(
      ringNumbers,
      circle(VisioSoilMarkGeometry.ringCentre, VisioSoilMarkGeometry.ringRadius),
    );
    expect(attribute(ring, 'strokeColor'), white);
    expect(
      double.parse(attribute(ring, 'strokeWidth')!),
      closeTo(VisioSoilMarkGeometry.ringStrokeWidth, 1e-9),
    );
    expect(attribute(ring, 'fillColor'), isNull);

    for (final (i, grain) in VisioSoilMarkGeometry.grains.indexed) {
      final path = paths[1 + i];
      final (commands, numbers) = parse(path);
      expect(commands, 'Maa');
      expectNumbers(numbers, circle(grain.centre, grain.radius));
      expect(attribute(path, 'fillColor'), white);
      expect(attribute(path, 'strokeColor'), isNull);
    }

    final handle = paths.last;
    final (handleCommands, handleNumbers) = parse(handle);
    expect(handleCommands, 'ML');
    expectNumbers(handleNumbers, [
      VisioSoilMarkGeometry.handleStart.dx,
      VisioSoilMarkGeometry.handleStart.dy,
      VisioSoilMarkGeometry.handleEnd.dx,
      VisioSoilMarkGeometry.handleEnd.dy,
    ]);
    expect(attribute(handle, 'strokeColor'), white);
    expect(
      double.parse(attribute(handle, 'strokeWidth')!),
      closeTo(VisioSoilMarkGeometry.handleStrokeWidth, 1e-9),
    );
    expect(attribute(handle, 'strokeLineCap'), 'round');
  });

  test('pre_android_12_launch_window_draws_the_tile_on_the_app_background', () {
    expect(
      style(read('values/styles.xml'), 'LaunchTheme')['android:windowBackground'],
      '@drawable/launch_background',
    );

    final items = layers(read('drawable/launch_background.xml'));
    expect(items, isNotEmpty);
    expect(attribute(items.first, 'drawable'), '@color/launch_background');
    expectTileThenMark(items, 'launch_background.xml');

    final variants = Directory(res)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last == 'launch_background.xml')
        .map((f) => f.parent.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toList();
    expect(
      variants,
      ['drawable'],
      reason: 'a qualified launch_background.xml shadows the one tested here',
    );
  });

  test('android_12_splash_shows_the_same_tile', () {
    final launch = style(read('values-v31/styles.xml'), 'LaunchTheme');
    expect(
      launch['android:windowSplashScreenBackground'],
      '@color/launch_background',
    );
    expect(
      launch['android:windowSplashScreenAnimatedIcon'],
      '@drawable/launch_icon',
    );
    expect(launch['android:windowBackground'], '@drawable/launch_background');
  });

  test('no_window_paints_the_template_background', () {
    expect(
      style(read('values/styles.xml'), 'NormalTheme')['android:windowBackground'],
      '@color/launch_background',
    );

    final styles = Directory(res)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last == 'styles.xml');
    for (final file in styles) {
      final text = file.readAsStringSync();
      expect(text, isNot(contains('Theme.Black')), reason: file.path);
      expect(text, isNot(contains('?android:colorBackground')), reason: file.path);
    }
  });
}
