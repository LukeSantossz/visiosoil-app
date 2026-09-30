/// The A4-sheet reader's first half: find the sheet, and rectify it at native
/// resolution (SPEC 0091, ADR 0017).
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

import 'patch_grid.dart';

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
  return (
    frame: RgbFrame(outWidth, outHeight, rgb),
    mmPerPx: mmPerPx,
    left: left,
    top: top,
  );
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
