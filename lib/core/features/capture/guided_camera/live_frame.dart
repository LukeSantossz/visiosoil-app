import 'dart:math' as math;
import 'dart:typed_data';

import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// The pixel layouts the camera streams: the luma plane of YUV 4:2:0 on
/// Android, BGRA on iOS (SPEC 0166).
enum LivePixelFormat { yuv420, bgra8888 }

/// The long side a preview frame is read at: `findSheet` searches a still at
/// `ceil(longSide / 1024)` reduction, so a frame of exactly 1024 px is
/// searched at about the resolution a 4000 to 4080 px still is.
const int liveLongSidePx = 1024;

/// A camera plane as the grey frame the reader reads: each pixel's grey
/// replicated into three channels. Rows are read through [bytesPerRow], so a
/// plane's padding is dropped.
///
/// The YUV luma is the grey itself; BGRA goes through the reader's own
/// [greyOf]. Every decision `findSheet` and `locateSoilDisc` take is on
/// `greyOf` of a pixel, which a replicated grey returns unchanged.
RgbFrame greyFrameFromPlane({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required LivePixelFormat format,
}) {
  final rgb = Uint8List(width * height * 3);
  var out = 0;
  for (var y = 0; y < height; y++) {
    final row = y * bytesPerRow;
    for (var x = 0; x < width; x++) {
      final int grey;
      switch (format) {
        case LivePixelFormat.yuv420:
          grey = bytes[row + x];
        case LivePixelFormat.bgra8888:
          final i = row + x * 4;
          grey = greyOf(bytes[i + 2], bytes[i + 1], bytes[i]);
      }
      rgb[out] = grey;
      rgb[out + 1] = grey;
      rgb[out + 2] = grey;
      out += 3;
    }
  }
  return RgbFrame(width, height, rgb);
}

/// [frame] turned clockwise by [degrees], one of 0, 90, 180 and 270: the
/// camera's sensor orientation, so the sheet's long side is vertical as it is
/// on the still.
RgbFrame rotateClockwise(RgbFrame frame, int degrees) {
  final w = frame.width;
  final h = frame.height;
  final (int outWidth, int outHeight) = switch (degrees) {
    0 || 180 => (w, h),
    90 || 270 => (h, w),
    _ => throw ArgumentError.value(degrees, 'degrees', 'not 0, 90, 180 or 270'),
  };
  if (degrees == 0) return frame;
  final source = frame.rgb;
  final rgb = Uint8List(outWidth * outHeight * 3);
  for (var y = 0; y < outHeight; y++) {
    for (var x = 0; x < outWidth; x++) {
      final (int sx, int sy) = switch (degrees) {
        90 => (y, h - 1 - x),
        180 => (w - 1 - x, h - 1 - y),
        _ => (w - 1 - y, x),
      };
      final from = (sy * w + sx) * 3;
      final to = (y * outWidth + x) * 3;
      rgb[to] = source[from];
      rgb[to + 1] = source[from + 1];
      rgb[to + 2] = source[from + 2];
    }
  }
  return RgbFrame(outWidth, outHeight, rgb);
}

/// [frame] at a long side of [liveLongSidePx], with the still's own bilinear
/// resize, or [frame] itself when it is no larger. Never enlarges.
RgbFrame reduceForReading(RgbFrame frame) {
  final long = math.max(frame.width, frame.height);
  if (long <= liveLongSidePx) return frame;
  int scaled(int side) => math.max(1, _roundHalfEven(side * liveLongSidePx / long));
  final width = frame.width == long ? liveLongSidePx : scaled(frame.width);
  final height = frame.height == long ? liveLongSidePx : scaled(frame.height);
  return resizeBilinear(frame, width, height);
}

/// Rounds half to even, as the patch grid's sizes are rounded.
int _roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final fraction = value - floor;
  if (fraction > 0.5) return floor.toInt() + 1;
  if (fraction < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}
