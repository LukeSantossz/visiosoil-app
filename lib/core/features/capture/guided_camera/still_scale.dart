import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';

/// The still's millimetres per pixel, estimated from a preview reading
/// (SPEC 0166): the sheet's long side over its length in the still's pixels.
///
/// [frame] and [still] are portrait sizes. The ratio between them is the
/// smaller of the two axes': where the preview is a crop of the still's field
/// of view, the axis it does not crop gives the exact ratio and the cropped
/// axis a larger one, so the minimum is exact there and errs toward "too
/// coarse" everywhere else.
double estimatedStillMmPerPx({
  required double sheetLongSidePx,
  required Size frame,
  required Size still,
}) {
  final ratio = math.min(still.width / frame.width, still.height / frame.height);
  return sheetHeightMm / (sheetLongSidePx * ratio);
}

/// Whether the still would be refused as `photographTooCoarse`: coarser than
/// the contract's canonical scale, the rule `resampleToCanonical` applies.
bool stillTooCoarse({
  required double sheetLongSidePx,
  required Size frame,
  required Size still,
  required double canonicalMmPerPx,
}) =>
    estimatedStillMmPerPx(
      sheetLongSidePx: sheetLongSidePx,
      frame: frame,
      still: still,
    ) >
    canonicalMmPerPx;

/// The size of the JPEG in [bytes] as displayed, portrait: the frame header's
/// width and height, swapped when the EXIF orientation turns it a quarter
/// (5 to 8). Null when the bytes are not a readable JPEG.
Size? portraitSizeOfJpeg(Uint8List bytes) {
  final info = img.JpegDecoder().startDecode(bytes);
  if (info == null) return null;
  final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
  final quarterTurned = orientation >= 5 && orientation <= 8;
  final width = (quarterTurned ? info.height : info.width).toDouble();
  final height = (quarterTurned ? info.width : info.height).toDouble();
  return Size(math.min(width, height), math.max(width, height));
}
