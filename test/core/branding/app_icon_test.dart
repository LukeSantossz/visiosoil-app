// Guard for the committed launcher-icon source. This runs in CI and proves the
// artifact matches the design-system tile; it does NOT rasterize (the generator
// under test/tools/ does that locally). See spec 0025.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

/// Signed distance, in viewBox units, from [p] to the mark drawn from
/// [VisioSoilMarkGeometry]: negative inside the ring, a grain or the handle.
double _markDistance(Offset p) {
  final ring =
      ((p - VisioSoilMarkGeometry.ringCentre).distance -
              VisioSoilMarkGeometry.ringRadius)
          .abs() -
      VisioSoilMarkGeometry.ringStrokeWidth / 2;
  var d = ring;
  for (final grain in VisioSoilMarkGeometry.grains) {
    d = math.min(d, (p - grain.centre).distance - grain.radius);
  }
  // The handle is a round-capped segment: distance to the segment minus half
  // its stroke.
  final a = VisioSoilMarkGeometry.handleStart;
  final ab = VisioSoilMarkGeometry.handleEnd - a;
  final t =
      (((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
              (ab.dx * ab.dx + ab.dy * ab.dy))
          .clamp(0.0, 1.0);
  final handle =
      (p - (a + ab * t)).distance - VisioSoilMarkGeometry.handleStrokeWidth / 2;
  return math.min(d, handle);
}

/// Pixels of [image] whose colour contradicts the mark drawn from the current
/// geometry at [markFraction] of the tile (the generator's placement). Only
/// pixels at least [marginPx] from any edge of the mark are judged, so
/// anti-aliasing can never decide the outcome (SPEC 0255).
List<String> _pixelsOffTheGeometry(
  img.Image image, {
  required double markFraction,
  required bool Function(img.Pixel) isMark,
  required bool Function(img.Pixel) isTile,
  double marginPx = 2.5,
}) {
  final dimension = image.width.toDouble();
  final markSize = dimension * markFraction;
  final offset = (dimension - markSize) / 2;
  final scale = markSize / VisioSoilMarkGeometry.viewBox;
  final wrong = <String>[];
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final unit = Offset(
        (x + 0.5 - offset) / scale,
        (y + 0.5 - offset) / scale,
      );
      final distancePx = _markDistance(unit) * scale;
      final pixel = image.getPixel(x, y);
      if (distancePx <= -marginPx && !isMark(pixel)) {
        wrong.add('($x, $y) should be mark');
      } else if (distancePx >= marginPx && !isTile(pixel)) {
        wrong.add('($x, $y) should be tile');
      }
    }
  }
  return wrong;
}

void main() {
  test('app_icon.png is the design-system green tile carrying a white mark', () {
    final file = File('assets/branding/app_icon.png');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'regenerate with: '
          'GENERATE_ICONS=1 flutter test test/tools/generate_app_icon_test.dart',
    );

    final image = img.decodePng(file.readAsBytesSync());
    expect(image, isNotNull);
    expect(image!.width, 1024);
    expect(image.height, 1024);

    // A corner is bare tile: the design-system primary green #4A7C59.
    final corner = image.getPixel(4, 4);
    expect(corner.r, closeTo(0x4A, 3));
    expect(corner.g, closeTo(0x7C, 3));
    expect(corner.b, closeTo(0x59, 3));

    // The white mark occupies the tile centre; find at least one white pixel.
    var whiteFound = false;
    for (var y = 300; y < 724 && !whiteFound; y += 4) {
      for (var x = 300; x < 724; x += 4) {
        final p = image.getPixel(x, y);
        if (p.r > 230 && p.g > 230 && p.b > 230) {
          whiteFound = true;
          break;
        }
      }
    }
    expect(
      whiteFound,
      isTrue,
      reason: 'the white brand mark must be present in the tile centre',
    );
  });

  test('app_icon_foreground.png is a transparent tile carrying a white mark', () {
    final file = File('assets/branding/app_icon_foreground.png');
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'regenerate with: '
          'GENERATE_ICONS=1 flutter test test/tools/generate_app_icon_test.dart',
    );

    final image = img.decodePng(file.readAsBytesSync());
    expect(image, isNotNull);
    expect(image!.width, 1024);
    expect(image.height, 1024);

    // The adaptive foreground has no tile: a corner must be fully transparent so
    // the green background layer shows through.
    expect(image.getPixel(4, 4).a, 0);

    // The white mark occupies the centre; find at least one opaque white pixel.
    var whiteFound = false;
    for (var y = 300; y < 724 && !whiteFound; y += 4) {
      for (var x = 300; x < 724; x += 4) {
        final p = image.getPixel(x, y);
        if (p.a > 200 && p.r > 230 && p.g > 230 && p.b > 230) {
          whiteFound = true;
          break;
        }
      }
    }
    expect(
      whiteFound,
      isTrue,
      reason: 'the white brand mark must be present in the foreground centre',
    );
  });

  group('committed_icons_follow_the_mark_geometry', () {
    // The generator (test/tools/) is CI-skipped, so nothing else proves the
    // committed sources were drawn from today's VisioSoilMarkGeometry rather
    // than an older one (SPEC 0255).
    bool white(img.Pixel p) => p.r > 230 && p.g > 230 && p.b > 230;

    test('app_icon.png is the mark at 60% of the green tile', () {
      final image = img.decodePng(
        File('assets/branding/app_icon.png').readAsBytesSync(),
      )!;
      final wrong = _pixelsOffTheGeometry(
        image,
        markFraction: 0.60,
        isMark: white,
        isTile: (p) =>
            (p.r - 0x4A).abs() <= 3 &&
            (p.g - 0x7C).abs() <= 3 &&
            (p.b - 0x59).abs() <= 3,
      );
      expect(
        wrong,
        isEmpty,
        reason:
            '${wrong.length} pixels off the geometry, first: '
            '${wrong.take(5).join('; ')}. Regenerate with GENERATE_ICONS=1 '
            'flutter test test/tools/generate_app_icon_test.dart',
      );
    });

    test(
      'app_icon_foreground.png is the mark at 90% of a transparent tile',
      () {
        final image = img.decodePng(
          File('assets/branding/app_icon_foreground.png').readAsBytesSync(),
        )!;
        final wrong = _pixelsOffTheGeometry(
          image,
          markFraction: 0.90,
          isMark: (p) => p.a > 200 && white(p),
          isTile: (p) => p.a <= 2,
        );
        expect(
          wrong,
          isEmpty,
          reason:
              '${wrong.length} pixels off the geometry, first: '
              '${wrong.take(5).join('; ')}. Regenerate with GENERATE_ICONS=1 '
              'flutter test test/tools/generate_app_icon_test.dart',
        );
      },
    );
  });
}
