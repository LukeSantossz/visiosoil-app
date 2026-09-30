/// The A4-sheet reader: find the sheet and rectify it at native resolution
/// (SPEC 0091), then find the soil on it and measure the photograph
/// (SPEC 0092, ADR 0017).
///
/// A bare A4 sheet is the scale reference the app reads. Its four corners give
/// the millimetres per pixel and the homography that corrects tilt. The sheet
/// is found by classical steps on a reduced grey copy of the photograph. It is
/// then rectified from the full-resolution frame at the sheet's own scale, so
/// the patch grid's byte-exact `BILINEAR` (ADR 0025) is still the resample that
/// takes it to the canonical scale.
///
/// Everything here is pure arithmetic over pixels: no model, no I/O, no state.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../classification_report.dart';
import 'patch_grid.dart';
import 'photograph_measurement.dart';

/// Why no sheet was read. Never a fallback, always a name (ADR 0017).
enum SheetRefusal {
  /// No sheet stands out from its surface: none is in the frame, or a pale
  /// sheet lies on a pale surface.
  notFound,

  /// The sheet runs off the frame, so its corners cannot all be seen.
  cropped,
}

/// A4, in millimetres.
const double sheetWidthMm = 210;
const double sheetHeightMm = 297;

/// The sheet's corners in the photograph, in pixels with a pixel's centre on
/// the integer. Ordered around the sheet so that the first edge is a short
/// (210 mm) one and the second a long (297 mm) one.
class SheetCorners {
  const SheetCorners(this.points);

  final List<({double x, double y})> points;
}

/// A rectangle on the rectified sheet, in millimetres from its origin, the
/// first corner of [SheetCorners].
class SheetRegion {
  const SheetRegion({
    required this.leftMm,
    required this.topMm,
    required this.widthMm,
    required this.heightMm,
  });

  final double leftMm;
  final double topMm;
  final double widthMm;
  final double heightMm;
}

/// The detection copy's long side, at most. Corners are refined to sub-pixel
/// there and scaled back, so detection needs no more resolution than this.
const _detectionLongSidePx = 1024;

/// The least difference between the bright and dark classes' mean grey that
/// reads as paper on a surface. Paper on a table is well over 100 apart. Noise
/// on a bare surface, or a pale sheet on a pale one, is well under this.
const _minContrast = 60.0;

/// A bright region filling more of the frame than this is not a sheet lying on
/// a surface. It is a pale surface, with or without a sheet on it.
const _maxSheetFraction = 0.9;

/// A bright region smaller than this is too small to be a sheet framed as the
/// protocol asks: the whole sheet in view, with a margin.
const _minSheetFraction = 0.05;

/// The hull is thinned to at most this many vertices before its largest
/// quadrilateral is searched exhaustively.
const _hullVertexBudget = 24;

/// How far inside the soil patch's edge the measured disc stays, so the grid's
/// outermost patch corners land on soil when the edge is irregular.
const double soilMarginMm = 2;

/// The coarse rectification the soil patch is located on: enough to resolve
/// the edge of a patch 8 to 10 cm across to half a millimetre.
const _coarsePxPerMm = 2;

/// The band along the sheet's edges that is ignored when looking for soil: the
/// paper's rim carries shadow, and the surface's colour bleeds into it.
const _rimMm = 5;

/// How far beyond the disc the native-resolution square reaches, so rounding
/// its bounds to whole pixels never shaves the disc.
const _squarePadMm = 1.0;

/// Measures [frame] on the A4 sheet: the sheet, the soil patch on it, and the
/// largest disc inside the patch, in the pixels of a native-resolution square
/// around that disc. Top-level, so it can be sent to the inference isolate
/// (SPEC 0083).
///
/// A sheet not found or cropped is refused by its name. A sheet with no soil
/// on it is [ClassificationFailureCause.soilRegionTooSmall], whose remedy is
/// the same: put soil on the sheet and spread it.
({PhotographMeasurement? measurement, ClassificationFailureCause? cause})
a4SheetMeasurer(RgbFrame frame) {
  final found = findSheet(frame);
  final corners = found.corners;
  if (corners == null) {
    return (
      measurement: null,
      cause: switch (found.refusal!) {
        SheetRefusal.notFound => ClassificationFailureCause.sheetNotFound,
        SheetRefusal.cropped => ClassificationFailureCause.sheetCropped,
      },
    );
  }

  final disc = locateSoilDisc(frame, corners);
  if (disc == null) {
    return (
      measurement: null,
      cause: ClassificationFailureCause.soilRegionTooSmall,
    );
  }

  final reach = disc.diameterMm / 2 + _squarePadMm;
  final square = rectifySheet(
    frame,
    corners,
    region: SheetRegion(
      leftMm: disc.xMm - reach,
      topMm: disc.yMm - reach,
      widthMm: 2 * reach,
      heightMm: 2 * reach,
    ),
  );
  // A millimetre x lies at x / mmPerPx in the rectified sheet's pixels, with
  // pixel i spanning [i, i + 1]. The width is rounded to whole pixels, so a
  // rectified pixel is square to within half a pixel across the sheet, which
  // the measurement's single scale already assumes.
  final mmPerPx = square.mmPerPx;
  return (
    measurement: PhotographMeasurement(
      frame: square.frame,
      mmPerPx: mmPerPx,
      centreYPx: disc.yMm / mmPerPx - square.top,
      centreXPx: disc.xMm / mmPerPx - square.left,
      diameterPx: disc.diameterMm / mmPerPx,
    ),
    cause: null,
  );
}

/// The largest disc of soil on the sheet, in millimetres from the sheet's
/// origin, or null when the sheet carries no soil.
///
/// The sheet is rectified coarsely, its rim is set aside, and soil is what
/// Otsu's threshold puts on the dark side of the rest. The patch is the largest
/// dark 4-connected component, with its holes filled. The disc's centre is the
/// patch's point farthest from paper, and its radius is that distance less
/// [soilMarginMm], so it holds only soil however irregular the patch is.
({double xMm, double yMm, double diameterMm})? locateSoilDisc(
  RgbFrame frame,
  SheetCorners corners,
) {
  final sheetWidth = (sheetWidthMm * _coarsePxPerMm).round();
  final sheetHeight = (sheetHeightMm * _coarsePxPerMm).round();
  final coarse = _sampled(
    frame,
    corners.points,
    sheetWidth,
    sheetHeight,
    left: 0,
    top: 0,
    right: sheetWidth,
    bottom: sheetHeight,
  );

  final rim = _rimMm * _coarsePxPerMm;
  final width = sheetWidth - 2 * rim;
  final height = sheetHeight - 2 * rim;
  // The negative, so that soil is the bright side and the component search
  // that finds the sheet finds the patch.
  final negative = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = ((y + rim) * sheetWidth + x + rim) * 3;
      negative[y * width + x] =
          255 - greyOf(coarse.rgb[i], coarse.rgb[i + 1], coarse.rgb[i + 2]);
    }
  }

  // A bare sheet splits too, into paper and slightly darker paper: the floor
  // that tells a sheet from its surface tells soil from paper.
  final split = _otsu(negative);
  if (split.brightMean - split.darkMean < _minContrast) return null;
  final patch = _filledLargestBright(negative, width, height, split.threshold);
  if (patch.area == 0) return null;

  final distance = _squaredDistanceOutside(patch.mask, width, height);
  var best = 0.0, bestX = 0, bestY = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final d = distance[y * width + x];
      if (d > best) {
        best = d;
        bestX = x;
        bestY = y;
      }
    }
  }
  // The patch's edge lies half a pixel before the nearest paper pixel's centre.
  final radiusMm = (math.sqrt(best) - 0.5) / _coarsePxPerMm - soilMarginMm;
  if (radiusMm <= 0) return null;
  return (
    xMm: (bestX + rim + 0.5) / _coarsePxPerMm,
    yMm: (bestY + rim + 0.5) / _coarsePxPerMm,
    diameterMm: 2 * radiusMm,
  );
}

/// Finds the sheet's four corners in [frame], or names why there are none.
({SheetCorners? corners, SheetRefusal? refusal}) findSheet(RgbFrame frame) {
  final factor = math.max(
    1,
    (math.max(frame.width, frame.height) / _detectionLongSidePx).ceil(),
  );
  final width = frame.width ~/ factor;
  final height = frame.height ~/ factor;
  final grey = _reducedGrey(frame, factor, width, height);

  final split = _otsu(grey);
  if (split.brightMean - split.darkMean < _minContrast) {
    return (corners: null, refusal: SheetRefusal.notFound);
  }

  final sheet = _filledLargestBright(grey, width, height, split.threshold);
  final fraction = sheet.area / (width * height);
  if (fraction > _maxSheetFraction || fraction < _minSheetFraction) {
    return (corners: null, refusal: SheetRefusal.notFound);
  }
  if (sheet.touchesBorder) {
    return (corners: null, refusal: SheetRefusal.cropped);
  }

  final boundary = _outerBoundary(sheet.mask, width, height);
  final hull = _thinned(_convexHull(boundary), _hullVertexBudget);
  if (hull.length < 4) {
    return (corners: null, refusal: SheetRefusal.notFound);
  }
  final quad = _largestQuadrilateral(hull);
  final refined = _refinedCorners(quad, boundary);
  if (refined == null || !_plausible(refined)) {
    return (corners: null, refusal: SheetRefusal.notFound);
  }

  // A detection pixel covers `factor` full-resolution pixels, so its centre
  // sits at x * factor + (factor - 1) / 2.
  final offset = (factor - 1) / 2;
  final corners = [
    for (final c in refined)
      (x: c.x * factor + offset, y: c.y * factor + offset),
  ];
  for (final c in corners) {
    if (c.x < 0 || c.y < 0 || c.x > frame.width - 1 || c.y > frame.height - 1) {
      return (corners: null, refusal: SheetRefusal.cropped);
    }
  }
  return (corners: SheetCorners(_ordered(corners)), refusal: null);
}

/// Rectifies the sheet at its own scale in [frame]: all of it, or only
/// [region].
///
/// The rectified sheet's long side spans as many pixels as the photographed
/// long edges do on average, so perspective is corrected with the scale close
/// to 1 : 1. [left] and [top] place a region's first pixel in the whole
/// rectified sheet, whose pixels a region reproduces exactly.
({RgbFrame frame, double mmPerPx, int left, int top}) rectifySheet(
  RgbFrame frame,
  SheetCorners corners, {
  SheetRegion? region,
}) {
  final p = corners.points;
  final longPx = (_distance(p[1], p[2]) + _distance(p[3], p[0])) / 2;
  final sheetHeight = longPx.round();
  final sheetWidth = (sheetHeight * sheetWidthMm / sheetHeightMm).round();
  final mmPerPx = sheetHeightMm / sheetHeight;
  final mmPerPxAcross = sheetWidthMm / sheetWidth;

  var left = 0, top = 0, right = sheetWidth, bottom = sheetHeight;
  if (region != null) {
    if (region.widthMm <= 0 || region.heightMm <= 0) {
      throw ArgumentError('a region needs a positive width and height');
    }
    left = (region.leftMm / mmPerPxAcross).round().clamp(0, sheetWidth);
    top = (region.topMm / mmPerPx).round().clamp(0, sheetHeight);
    right = ((region.leftMm + region.widthMm) / mmPerPxAcross).round().clamp(
      left,
      sheetWidth,
    );
    bottom = ((region.topMm + region.heightMm) / mmPerPx).round().clamp(
      top,
      sheetHeight,
    );
    if (right == left || bottom == top) {
      throw ArgumentError('the region lies outside the sheet');
    }
  }

  return (
    frame: _sampled(
      frame,
      p,
      sheetWidth,
      sheetHeight,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    ),
    mmPerPx: mmPerPx,
    left: left,
    top: top,
  );
}

/// Columns [left] to [right] and rows [top] to [bottom] of the sheet rectified
/// to [sheetWidth] by [sheetHeight] pixels.
RgbFrame _sampled(
  RgbFrame frame,
  List<({double x, double y})> p,
  int sheetWidth,
  int sheetHeight, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  // The rectified sheet's pixel grid spans [-1/2, W - 1/2] with a pixel's centre
  // on the integer, so its corners map onto the photographed ones.
  final h = _homography([
    (x: -0.5, y: -0.5),
    (x: sheetWidth - 0.5, y: -0.5),
    (x: sheetWidth - 0.5, y: sheetHeight - 0.5),
    (x: -0.5, y: sheetHeight - 0.5),
  ], p);

  final outWidth = right - left;
  final outHeight = bottom - top;
  final rgb = Uint8List(outWidth * outHeight * 3);
  for (var j = 0; j < outHeight; j++) {
    final v = (top + j).toDouble();
    for (var i = 0; i < outWidth; i++) {
      final u = (left + i).toDouble();
      final w = h[6] * u + h[7] * v + 1;
      final x = (h[0] * u + h[1] * v + h[2]) / w;
      final y = (h[3] * u + h[4] * v + h[5]) / w;
      _sampleBilinear(frame, x, y, rgb, (j * outWidth + i) * 3);
    }
  }
  return RgbFrame(outWidth, outHeight, rgb);
}

/// The squared Euclidean distance from each pixel of [mask] to the nearest
/// pixel outside it, exactly: Felzenszwalb and Huttenlocher's lower envelope of
/// parabolas, down each column and then along each row. Beyond the grid counts
/// as outside, so a patch touching the grid's edge is measured to that edge.
Float64List _squaredDistanceOutside(Uint8List mask, int width, int height) {
  // A one-pixel frame of outside around the grid, so every column and every
  // row holds an outside pixel and every distance is finite.
  final w = width + 2, h = height + 2;
  final far = ((w + h) * (w + h)).toDouble();
  final grid = Float64List(w * h);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (mask[y * width + x] == 1) grid[(y + 1) * w + x + 1] = far;
    }
  }

  final n = math.max(w, h);
  final line = Float64List(n), out = Float64List(n);
  final sites = Int32List(n), bounds = Float64List(n + 1);
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      line[y] = grid[y * w + x];
    }
    _lowerEnvelope(line, h, out, sites, bounds);
    for (var y = 0; y < h; y++) {
      grid[y * w + x] = out[y];
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      line[x] = grid[y * w + x];
    }
    _lowerEnvelope(line, w, out, sites, bounds);
    for (var x = 0; x < w; x++) {
      grid[y * w + x] = out[x];
    }
  }

  final distance = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      distance[y * width + x] = grid[(y + 1) * w + x + 1];
    }
  }
  return distance;
}

/// The one-dimensional squared distance transform of the first [n] values of
/// [f], into [out]: out[q] is the least (q - p)^2 + f[p] over every p.
void _lowerEnvelope(
  Float64List f,
  int n,
  Float64List out,
  Int32List sites,
  Float64List bounds,
) {
  double meet(int q, int p) =>
      ((f[q] + q * q) - (f[p] + p * p)) / (2 * q - 2 * p);

  var k = 0;
  sites[0] = 0;
  bounds[0] = double.negativeInfinity;
  bounds[1] = double.infinity;
  for (var q = 1; q < n; q++) {
    var s = meet(q, sites[k]);
    while (s <= bounds[k]) {
      k--;
      s = meet(q, sites[k]);
    }
    k++;
    sites[k] = q;
    bounds[k] = s;
    bounds[k + 1] = double.infinity;
  }
  k = 0;
  for (var q = 0; q < n; q++) {
    while (bounds[k + 1] < q) {
      k++;
    }
    final d = q - sites[k];
    out[q] = d * d + f[sites[k]];
  }
}

Uint8List _reducedGrey(RgbFrame frame, int factor, int width, int height) {
  final grey = Uint8List(width * height);
  final n = factor * factor;
  final rgb = frame.rgb;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      for (var dy = 0; dy < factor; dy++) {
        var i = ((y * factor + dy) * frame.width + x * factor) * 3;
        for (var dx = 0; dx < factor; dx++, i += 3) {
          sum += greyOf(rgb[i], rgb[i + 1], rgb[i + 2]);
        }
      }
      grey[y * width + x] = (sum + n ~/ 2) ~/ n;
    }
  }
  return grey;
}

({int threshold, double darkMean, double brightMean}) _otsu(Uint8List grey) {
  final histogram = List<int>.filled(256, 0);
  for (final value in grey) {
    histogram[value]++;
  }
  final total = grey.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }
  var darkCount = 0, darkSum = 0.0, best = -1.0;
  var threshold = 0, darkMean = 0.0, brightMean = 0.0;
  for (var t = 0; t < 255; t++) {
    darkCount += histogram[t];
    if (darkCount == 0) continue;
    final brightCount = total - darkCount;
    if (brightCount == 0) break;
    darkSum += t * histogram[t];
    final mDark = darkSum / darkCount;
    final mBright = (sum - darkSum) / brightCount;
    final between =
        darkCount * brightCount * (mDark - mBright) * (mDark - mBright);
    if (between > best) {
      best = between;
      threshold = t;
      darkMean = mDark;
      brightMean = mBright;
    }
  }
  return (threshold: threshold, darkMean: darkMean, brightMean: brightMean);
}

/// The largest bright 4-connected component, with its holes filled: the soil
/// patch on the sheet must not open a second boundary inside it.
({Uint8List mask, int area, bool touchesBorder}) _filledLargestBright(
  Uint8List grey,
  int width,
  int height,
  int threshold,
) {
  final labels = Int32List(width * height);
  final queue = Int32List(width * height);
  var bestLabel = 0, bestArea = 0, label = 0;
  for (var start = 0; start < grey.length; start++) {
    if (grey[start] <= threshold || labels[start] != 0) continue;
    label++;
    var head = 0, tail = 0, area = 0;
    queue[tail++] = start;
    labels[start] = label;
    while (head < tail) {
      final p = queue[head++];
      area++;
      final x = p % width, y = p ~/ width;
      if (x > 0) {
        tail = _visit(p - 1, grey, threshold, labels, label, queue, tail);
      }
      if (x < width - 1) {
        tail = _visit(p + 1, grey, threshold, labels, label, queue, tail);
      }
      if (y > 0) {
        tail = _visit(p - width, grey, threshold, labels, label, queue, tail);
      }
      if (y < height - 1) {
        tail = _visit(p + width, grey, threshold, labels, label, queue, tail);
      }
    }
    if (area > bestArea) {
      bestArea = area;
      bestLabel = label;
    }
  }

  // Whatever outside the component the frame's border can reach is surface;
  // what it cannot reach is a hole in the sheet.
  final mask = Uint8List(width * height);
  for (var i = 0; i < mask.length; i++) {
    if (bestLabel != 0 && labels[i] == bestLabel) mask[i] = 1;
  }
  final reached = Uint8List(width * height);
  var head = 0, tail = 0;
  void seed(int p) {
    if (mask[p] == 0 && reached[p] == 0) {
      reached[p] = 1;
      queue[tail++] = p;
    }
  }

  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }
  while (head < tail) {
    final p = queue[head++];
    final x = p % width, y = p ~/ width;
    if (x > 0) seed(p - 1);
    if (x < width - 1) seed(p + 1);
    if (y > 0) seed(p - width);
    if (y < height - 1) seed(p + width);
  }

  var area = 0;
  var touches = false;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 0 && reached[i] == 0) mask[i] = 1;
    if (mask[i] == 1) {
      area++;
      final x = i % width, y = i ~/ width;
      if (x == 0 || y == 0 || x == width - 1 || y == height - 1) touches = true;
    }
  }
  return (mask: mask, area: area, touchesBorder: touches);
}

int _visit(
  int p,
  Uint8List grey,
  int threshold,
  Int32List labels,
  int label,
  Int32List queue,
  int tail,
) {
  if (grey[p] > threshold && labels[p] == 0) {
    labels[p] = label;
    queue[tail++] = p;
  }
  return tail;
}

List<({double x, double y})> _outerBoundary(
  Uint8List mask,
  int width,
  int height,
) {
  final points = <({double x, double y})>[];
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      if (mask[i] == 0) continue;
      if (mask[i - 1] == 0 ||
          mask[i + 1] == 0 ||
          mask[i - width] == 0 ||
          mask[i + width] == 0) {
        points.add((x: x.toDouble(), y: y.toDouble()));
      }
    }
  }
  return points;
}

/// Andrew's monotone chain.
List<({double x, double y})> _convexHull(List<({double x, double y})> points) {
  final sorted = [...points]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  double cross(
    ({double x, double y}) o,
    ({double x, double y}) a,
    ({double x, double y}) b,
  ) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  final lower = <({double x, double y})>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <({double x, double y})>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [
    ...lower.sublist(0, lower.length - 1),
    ...upper.sublist(0, upper.length - 1),
  ];
}

/// Drops the vertex that adds the least area, until [budget] remain. The
/// corners of a quadrilateral add the most, so they are the last to go.
List<({double x, double y})> _thinned(
  List<({double x, double y})> hull,
  int budget,
) {
  final polygon = [...hull];
  while (polygon.length > budget) {
    var weakest = 0;
    var least = double.infinity;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[(i - 1 + polygon.length) % polygon.length];
      final b = polygon[i];
      final c = polygon[(i + 1) % polygon.length];
      final area = ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
          .abs();
      if (area < least) {
        least = area;
        weakest = i;
      }
    }
    polygon.removeAt(weakest);
  }
  return polygon;
}

List<({double x, double y})> _largestQuadrilateral(
  List<({double x, double y})> hull,
) {
  var best = -1.0;
  var quad = hull.sublist(0, 4);
  final n = hull.length;
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      for (var c = b + 1; c < n; c++) {
        for (var d = c + 1; d < n; d++) {
          final candidate = [hull[a], hull[b], hull[c], hull[d]];
          final area = _area(candidate);
          if (area > best) {
            best = area;
            quad = candidate;
          }
        }
      }
    }
  }
  return quad;
}

double _area(List<({double x, double y})> polygon) {
  var twice = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    twice += a.x * b.y - b.x * a.y;
  }
  return twice.abs() / 2;
}

/// Each edge refitted by total least squares through the boundary points near
/// its middle, then moved half a pixel outward, since a boundary pixel's centre
/// lies half a pixel inside the edge it borders. The corners are the refitted
/// lines' intersections.
List<({double x, double y})>? _refinedCorners(
  List<({double x, double y})> quad,
  List<({double x, double y})> boundary,
) {
  final centre = (
    x: quad.map((p) => p.x).reduce((a, b) => a + b) / 4,
    y: quad.map((p) => p.y).reduce((a, b) => a + b) / 4,
  );
  final lines = <({double nx, double ny, double c})>[];
  for (var i = 0; i < 4; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % 4];
    final length = _distance(a, b);
    final dx = (b.x - a.x) / length, dy = (b.y - a.y) / length;
    final reach = math.max(3.0, 0.01 * length);

    var sx = 0.0, sy = 0.0, count = 0;
    final near = <({double x, double y})>[];
    for (final p in boundary) {
      final along = (p.x - a.x) * dx + (p.y - a.y) * dy;
      final across = (-(p.x - a.x) * dy + (p.y - a.y) * dx).abs();
      if (across <= reach && along >= 0.1 * length && along <= 0.9 * length) {
        near.add(p);
        sx += p.x;
        sy += p.y;
        count++;
      }
    }

    double nx, ny, c;
    if (count < 10) {
      nx = -dy;
      ny = dx;
      c = nx * a.x + ny * a.y;
    } else {
      final mx = sx / count, my = sy / count;
      var sxx = 0.0, sxy = 0.0, syy = 0.0;
      for (final p in near) {
        sxx += (p.x - mx) * (p.x - mx);
        sxy += (p.x - mx) * (p.y - my);
        syy += (p.y - my) * (p.y - my);
      }
      final theta = 0.5 * math.atan2(2 * sxy, sxx - syy);
      nx = -math.sin(theta);
      ny = math.cos(theta);
      c = nx * mx + ny * my;
    }
    // Point the normal away from the sheet, then step half a pixel along it.
    if (nx * centre.x + ny * centre.y - c > 0) {
      nx = -nx;
      ny = -ny;
      c = -c;
    }
    lines.add((nx: nx, ny: ny, c: c + 0.5));
  }

  final corners = <({double x, double y})>[];
  for (var i = 0; i < 4; i++) {
    final l1 = lines[(i + 3) % 4];
    final l2 = lines[i];
    final determinant = l1.nx * l2.ny - l1.ny * l2.nx;
    if (determinant.abs() < 1e-9) return null;
    corners.add((
      x: (l1.c * l2.ny - l1.ny * l2.c) / determinant,
      y: (l1.nx * l2.c - l1.c * l2.nx) / determinant,
    ));
  }
  return corners;
}

/// Convex, and no edge shorter than half its opposite: a photograph from above
/// cannot foreshorten a sheet further than that.
bool _plausible(List<({double x, double y})> quad) {
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = quad[i], b = quad[(i + 1) % 4], c = quad[(i + 2) % 4];
    final turn = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (turn == 0) return false;
    sign ??= turn.sign;
    if (turn.sign != sign) return false;
  }
  for (var i = 0; i < 2; i++) {
    final one = _distance(quad[i], quad[i + 1]);
    final other = _distance(quad[i + 2], quad[(i + 3) % 4]);
    if (math.min(one, other) < 0.5 * math.max(one, other)) return false;
  }
  return true;
}

/// Puts a short edge first and a long edge second, starting from whichever end
/// of a short edge lies nearer the photograph's top-left, so the order does not
/// depend on where the hull happened to begin.
List<({double x, double y})> _ordered(List<({double x, double y})> quad) {
  final firstPair = _distance(quad[0], quad[1]) + _distance(quad[2], quad[3]);
  final secondPair = _distance(quad[1], quad[2]) + _distance(quad[3], quad[0]);
  final start = firstPair <= secondPair ? 0 : 1;
  final a = start, b = start + 2;
  final first = quad[a].x + quad[a].y <= quad[b].x + quad[b].y ? a : b;
  return [for (var k = 0; k < 4; k++) quad[(first + k) % 4]];
}

double _distance(({double x, double y}) a, ({double x, double y}) b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// The projective map taking each of [from] onto the matching [to], as the
/// eight coefficients of (h0 u + h1 v + h2, h3 u + h4 v + h5) / (h6 u + h7 v + 1).
List<double> _homography(
  List<({double x, double y})> from,
  List<({double x, double y})> to,
) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var k = 0; k < 4; k++) {
    final u = from[k].x, v = from[k].y, x = to[k].x, y = to[k].y;
    a[2 * k]
      ..[0] = u
      ..[1] = v
      ..[2] = 1
      ..[6] = -x * u
      ..[7] = -x * v
      ..[8] = x;
    a[2 * k + 1]
      ..[3] = u
      ..[4] = v
      ..[5] = 1
      ..[6] = -y * u
      ..[7] = -y * v
      ..[8] = y;
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    final swap = a[col];
    a[col] = a[pivot];
    a[pivot] = swap;
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final factor = a[r][col] / a[col][col];
      for (var c = col; c < 9; c++) {
        a[r][c] -= factor * a[col][c];
      }
    }
  }
  return [for (var r = 0; r < 8; r++) a[r][8] / a[r][r]];
}

/// Bilinear interpolation at (x, y), a pixel's centre on the integer, clamped
/// at the frame's edge. Writes three bytes into [out] at [at].
void _sampleBilinear(
  RgbFrame frame,
  double x,
  double y,
  Uint8List out,
  int at,
) {
  final maxX = frame.width - 1, maxY = frame.height - 1;
  final cx = x.clamp(0.0, maxX.toDouble());
  final cy = y.clamp(0.0, maxY.toDouble());
  final x0 = cx.floor(), y0 = cy.floor();
  final x1 = math.min(x0 + 1, maxX), y1 = math.min(y0 + 1, maxY);
  final fx = cx - x0, fy = cy - y0;
  final rgb = frame.rgb;
  final i00 = (y0 * frame.width + x0) * 3;
  final i10 = (y0 * frame.width + x1) * 3;
  final i01 = (y1 * frame.width + x0) * 3;
  final i11 = (y1 * frame.width + x1) * 3;
  for (var k = 0; k < 3; k++) {
    final top = rgb[i00 + k] + (rgb[i10 + k] - rgb[i00 + k]) * fx;
    final bottom = rgb[i01 + k] + (rgb[i11 + k] - rgb[i01 + k]) * fx;
    out[at + k] = (top + (bottom - top) * fy + 0.5).floor().clamp(0, 255);
  }
}
