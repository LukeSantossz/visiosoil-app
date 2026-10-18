import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_frame.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// The grey value at (x, y) of a frame whose three channels are equal.
int _grey(RgbFrame frame, int x, int y) {
  final i = (y * frame.width + x) * 3;
  expect(frame.rgb[i + 1], frame.rgb[i], reason: 'green equals red at ($x, $y)');
  expect(frame.rgb[i + 2], frame.rgb[i], reason: 'blue equals red at ($x, $y)');
  return frame.rgb[i];
}

/// A grey frame of [width] × [height] whose pixel (x, y) is y * width + x.
RgbFrame _numbered(int width, int height) {
  final rgb = Uint8List(width * height * 3);
  for (var i = 0; i < width * height; i++) {
    rgb[i * 3] = rgb[i * 3 + 1] = rgb[i * 3 + 2] = i;
  }
  return RgbFrame(width, height, rgb);
}

void main() {
  test('yuv_luma_drops_row_padding', () {
    // A 4 × 2 luma plane with two bytes of padding at the end of each row.
    final bytes = Uint8List.fromList([10, 20, 30, 40, 99, 99, 50, 60, 70, 80, 99, 99]);
    final frame = greyFrameFromPlane(
      bytes: bytes,
      width: 4,
      height: 2,
      bytesPerRow: 6,
      format: LivePixelFormat.yuv420,
    );
    expect([frame.width, frame.height], [4, 2]);
    expect(
      [for (var y = 0; y < 2; y++) for (var x = 0; x < 4; x++) _grey(frame, x, y)],
      [10, 20, 30, 40, 50, 60, 70, 80],
    );
  });

  test('bgra_converts_to_the_readers_grey', () {
    // A 2 × 2 BGRA plane, four bytes of padding per row.
    final pixels = [
      (b: 10, g: 200, r: 30),
      (b: 255, g: 0, r: 0),
      (b: 0, g: 0, r: 255),
      (b: 90, g: 120, r: 150),
    ];
    final bytes = Uint8List(2 * 12);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        final p = pixels[y * 2 + x];
        final i = y * 12 + x * 4;
        bytes
          ..[i] = p.b
          ..[i + 1] = p.g
          ..[i + 2] = p.r
          ..[i + 3] = 255;
      }
    }
    final frame = greyFrameFromPlane(
      bytes: bytes,
      width: 2,
      height: 2,
      bytesPerRow: 12,
      format: LivePixelFormat.bgra8888,
    );
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 2; x++) {
        final p = pixels[y * 2 + x];
        expect(_grey(frame, x, y), greyOf(p.r, p.g, p.b));
      }
    }
  });

  test('the_frame_is_turned_portrait', () {
    final source = _numbered(3, 2); // w = 3, h = 2
    int at(RgbFrame f, int x, int y) => _grey(f, x, y);
    int src(int x, int y) => y * 3 + x;

    final r0 = rotateClockwise(source, 0);
    expect([r0.width, r0.height], [3, 2]);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        expect(at(r0, x, y), src(x, y));
      }
    }

    final r90 = rotateClockwise(source, 90);
    expect([r90.width, r90.height], [2, 3]);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 2; x++) {
        expect(at(r90, x, y), src(y, 2 - 1 - x), reason: '90 ($x, $y)');
      }
    }

    final r180 = rotateClockwise(source, 180);
    expect([r180.width, r180.height], [3, 2]);
    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 3; x++) {
        expect(at(r180, x, y), src(3 - 1 - x, 2 - 1 - y), reason: '180 ($x, $y)');
      }
    }

    final r270 = rotateClockwise(source, 270);
    expect([r270.width, r270.height], [2, 3]);
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 2; x++) {
        expect(at(r270, x, y), src(3 - 1 - y, x), reason: '270 ($x, $y)');
      }
    }

    expect(() => rotateClockwise(source, 45), throwsArgumentError);
  });

  test('a_large_frame_is_read_at_1024', () {
    for (final (w, h, ew, eh) in [
      (1920, 1080, 1024, 576),
      (4000, 3000, 1024, 768),
      (1280, 721, 1024, 577),
      // 1025 × 0.5 = 512.5 rounds half to even.
      (2048, 1025, 1024, 512),
      (800, 600, 800, 600),
    ]) {
      final frame = _numbered(w, h);
      final reduced = reduceForReading(frame);
      expect([reduced.width, reduced.height], [ew, eh], reason: '$w × $h');
      if (w > liveLongSidePx || h > liveLongSidePx) {
        expect(reduced.rgb, resizeBilinear(frame, ew, eh).rgb, reason: '$w × $h');
      } else {
        expect(identical(reduced, frame), isTrue, reason: 'never enlarged');
      }
    }
  });
}
