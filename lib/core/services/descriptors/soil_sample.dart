import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// The soil sample shown in place of the photograph (SPEC 0172): a square on
/// the sheet, straightened, centred on the soil disc the classifier reads.

/// How far past the disc the square reaches on every side.
const double soilSampleMarginMm = 15;

/// The sample's longest side, in pixels.
const int soilSampleMaxSidePx = 1024;

/// The square on the sheet around [disc]: [soilSampleMarginMm] past it on
/// every side, centred on it, and narrowed equally on every side where the
/// sheet's edge is nearer.
SheetRegion soilSampleRegion(
  ({double xMm, double yMm, double diameterMm}) disc,
) {
  final half = [
    disc.diameterMm / 2 + soilSampleMarginMm,
    disc.xMm,
    disc.yMm,
    sheetWidthMm - disc.xMm,
    sheetHeightMm - disc.yMm,
  ].reduce(math.min);
  return SheetRegion(
    leftMm: disc.xMm - half,
    topMm: disc.yMm - half,
    widthMm: 2 * half,
    heightMm: 2 * half,
  );
}

/// [image] cut to a square on its shorter side, centred: the rectified region
/// is square in millimetres, but its sides are rounded to whole pixels apart.
img.Image squareSample(img.Image image) {
  final side = math.min(image.width, image.height);
  if (image.width == side && image.height == side) return image;
  return img.copyCrop(
    image,
    x: (image.width - side) ~/ 2,
    y: (image.height - side) ~/ 2,
    width: side,
    height: side,
  );
}

/// The sample of the photograph at [imagePath] as JPEG bytes, measured as the
/// classifier measures it, or null when the file cannot be read or holds no
/// readable sheet or soil disc. Top-level, so it can run in an isolate.
Uint8List? soilSampleJpeg(String imagePath) {
  final file = File(imagePath);
  if (!file.existsSync()) return null;
  img.Image? image;
  try {
    image = img.decodeImage(file.readAsBytesSync());
  } catch (e) {
    // A corrupt file can overrun the decoder, as in `runInference`.
    developer.log('decode failed: $e', name: 'SoilSample');
  }
  if (image == null) return null;

  final frame = InferenceService.frameOf(img.bakeOrientation(image));
  final corners = findSheet(frame).corners;
  if (corners == null) return null;
  final disc = locateSoilDisc(frame, corners);
  if (disc == null) return null;

  final square = rectifySheet(
    frame,
    corners,
    region: soilSampleRegion(disc),
  ).frame;
  var sample = squareSample(
    img.Image.fromBytes(
      width: square.width,
      height: square.height,
      bytes: square.rgb.buffer,
      numChannels: 3,
    ),
  );
  final side = math.max(sample.width, sample.height);
  if (side > soilSampleMaxSidePx) {
    sample = img.copyResize(
      sample,
      width: sample.width * soilSampleMaxSidePx ~/ side,
      height: sample.height * soilSampleMaxSidePx ~/ side,
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodeJpg(sample, quality: 85);
}
