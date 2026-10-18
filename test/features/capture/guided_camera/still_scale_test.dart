import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/features/capture/guided_camera/still_scale.dart';

const _canonical = 0.12920342774728033;

void main() {
  test('the_scale_estimate_uses_the_uncropped_axis', () {
    const still = Size(3000, 4000);
    const frame = Size(576, 1024);
    // The preview crops the still's width; the height is uncropped.
    expect(
      estimatedStillMmPerPx(sheetLongSidePx: 900, frame: frame, still: still),
      closeTo(297 / (900 * 4000 / 1024), 1e-12),
    );
    expect(
      stillTooCoarse(
        sheetLongSidePx: 900,
        frame: frame,
        still: still,
        canonicalMmPerPx: _canonical,
      ),
      isFalse,
    );
    expect(
      stillTooCoarse(
        sheetLongSidePx: 500,
        frame: frame,
        still: still,
        canonicalMmPerPx: _canonical,
      ),
      isTrue,
    );
  });

  test('the_still_size_is_learned', () {
    final landscape = img.encodeJpg(img.Image(width: 40, height: 30));
    final rotated = img.ExifData()..imageIfd.orientation = 6;
    final sideways = img.injectJpgExif(landscape, rotated)!;
    expect(portraitSizeOfJpeg(sideways), const Size(30, 40));

    final portrait = img.encodeJpg(img.Image(width: 30, height: 40));
    final upright = img.ExifData()..imageIfd.orientation = 1;
    expect(portraitSizeOfJpeg(img.injectJpgExif(portrait, upright)!),
        const Size(30, 40));
    // No EXIF at all reads the frame header as it is.
    expect(portraitSizeOfJpeg(portrait), const Size(30, 40));
  });
}
