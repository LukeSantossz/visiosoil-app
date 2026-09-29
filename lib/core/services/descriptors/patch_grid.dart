/// The canonical patch grid: a photograph at a measured scale in, the grey
/// patches the descriptors read out (SPEC 0081, ADR 0025).
///
/// This is `ml/src/dataset.py`'s `_photograph_patches` and `ml/src/patches.py`
/// ported, and the rule is identical arithmetic, not approximately equal
/// pixels. The resample is Pillow 10.4's `BILINEAR` (`libImaging/Resample.c`)
/// in its own operation order, every rounding is Python's half to even, and the
/// grid's step count is Python's float floor division.
/// `test/fixtures/patches/golden.json` holds the two languages together byte
/// for byte. Nothing here calls a libm function other than `sqrt`, which IEEE
/// rounds correctly, so the equality holds on any CPU.
///
/// Everything here is pure arithmetic over pixels: no model, no I/O, no state.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../image_quality/luma.dart';

/// Why a photograph produced no patches, as `src.patches.PatchRefusal` names
/// it. Never a fallback, always a name.
enum PatchRefusal {
  /// The photograph is coarser than the canonical, so reaching the canonical
  /// would upsample and invent grain that was never photographed.
  tooCoarse,

  /// The region carries fewer patches than the floor.
  regionTooSmall,

  /// The grid does not fit in the frame: the region is not wholly photographed.
  outsideFrame,
}

/// An RGB photograph, row-major, three interleaved bytes per pixel, already
/// decoded and oriented.
class RgbFrame {
  RgbFrame(this.width, this.height, this.rgb) {
    if (width <= 0 || height <= 0 || rgb.length != width * height * 3) {
      throw ArgumentError(
        'a $width x $height frame holds ${width * height * 3} bytes; '
        'got ${rgb.length}',
      );
    }
  }

  final int width;
  final int height;
  final Uint8List rgb;
}

/// Where the patches of one region sit, and how big they are.
class PatchGeometry {
  const PatchGeometry._({
    required this.patchPx,
    required this.patchMm,
    required this.stridePx,
    required this.insetPx,
    required this.regionRadiusPx,
    required this.offsets,
  });

  final int patchPx;
  final double patchMm;
  final double stridePx;
  final double insetPx;
  final double regionRadiusPx;

  /// Patch centres as `(dy, dx)` from the region centre, sorted as Python sorts
  /// the tuples.
  final List<(double, double)> offsets;

  int get count => offsets.length;
}

/// The grey patches of one photograph, or the refusal: `_photograph_patches`
/// from its resample onwards.
///
/// [centreYPx], [centreXPx] and [diameterPx] locate the region in [frame]'s own
/// pixels. The four geometry values are the ones the descriptor contract
/// carries. Each patch is a `patchPx × patchPx` grey plane, in the order
/// `describePatch` expects them to be averaged in.
({List<Uint8List>? patches, PatchRefusal? refusal}) canonicalPatches(
  RgbFrame frame, {
  required double measuredMmPerPx,
  required double centreYPx,
  required double centreXPx,
  required double diameterPx,
  required double canonicalMmPerPx,
  required int patchPx,
  required double strideFraction,
  required int minPatches,
}) {
  // `_canonical_region`: the too-coarse refusal comes first, then the region
  // travels into canonical pixels by the resample's own ratio.
  if (measuredMmPerPx > canonicalMmPerPx) {
    return (patches: null, refusal: PatchRefusal.tooCoarse);
  }
  final ratio = measuredMmPerPx / canonicalMmPerPx;
  final centreY = centreYPx * ratio;
  final centreX = centreXPx * ratio;
  final diameter = diameterPx * ratio;

  final canonical = resampleToCanonical(
    frame,
    measuredMmPerPx: measuredMmPerPx,
    canonicalMmPerPx: canonicalMmPerPx,
  ).frame!;

  // `cut_patches`: the geometry, the grey plane, the frame check, the cut.
  final placed = patchGeometry(
    regionDiameterPx: diameter,
    patchPx: patchPx,
    canonicalMmPerPx: canonicalMmPerPx,
    minPatches: minPatches,
    strideFraction: strideFraction,
  );
  final geometry = placed.geometry;
  if (geometry == null) return (patches: null, refusal: placed.refusal);

  final grey = _greyPlane(canonical);
  final half = patchPx / 2.0;
  final corners = [
    for (final (dy, dx) in geometry.offsets)
      (
        _roundHalfEven(centreY + dy - half),
        _roundHalfEven(centreX + dx - half),
      ),
  ];
  for (final (top, left) in corners) {
    if (top < 0 ||
        left < 0 ||
        top + patchPx > canonical.height ||
        left + patchPx > canonical.width) {
      return (patches: null, refusal: PatchRefusal.outsideFrame);
    }
  }

  final patches = <Uint8List>[];
  for (final (top, left) in corners) {
    final patch = Uint8List(patchPx * patchPx);
    for (var row = 0; row < patchPx; row++) {
      final start = (top + row) * canonical.width + left;
      patch.setRange(row * patchPx, (row + 1) * patchPx, grey, start);
    }
    patches.add(patch);
  }
  return (patches: patches, refusal: null);
}

/// [frame] at the canonical scale, or the refusal to upsample it:
/// `resample_to_canonical`.
///
/// A frame already at the canonical is returned as it is. Throws an
/// [ArgumentError] for a scale that is not positive.
({RgbFrame? frame, PatchRefusal? refusal}) resampleToCanonical(
  RgbFrame frame, {
  required double measuredMmPerPx,
  required double canonicalMmPerPx,
}) {
  if (!(measuredMmPerPx > 0.0) || !(canonicalMmPerPx > 0.0)) {
    throw ArgumentError(
      'a scale must be positive; got measured $measuredMmPerPx and '
      'canonical $canonicalMmPerPx',
    );
  }
  if (measuredMmPerPx > canonicalMmPerPx) {
    return (frame: null, refusal: PatchRefusal.tooCoarse);
  }
  if (measuredMmPerPx == canonicalMmPerPx) {
    return (frame: frame, refusal: null);
  }
  final ratio = measuredMmPerPx / canonicalMmPerPx;
  final width = math.max(1, _roundHalfEven(frame.width * ratio));
  final height = math.max(1, _roundHalfEven(frame.height * ratio));
  return (frame: _resizeBilinear(frame, width, height), refusal: null);
}

/// The grid a region of this size carries, or the refusal: `patch_geometry`.
///
/// Throws an [ArgumentError] for a diameter or a patch side that is not
/// positive.
({PatchGeometry? geometry, PatchRefusal? refusal}) patchGeometry({
  required double regionDiameterPx,
  required int patchPx,
  required double canonicalMmPerPx,
  required int minPatches,
  required double strideFraction,
}) {
  if (!(regionDiameterPx > 0.0)) {
    throw ArgumentError(
      'region diameter must be positive; got $regionDiameterPx',
    );
  }
  if (patchPx <= 0) {
    throw ArgumentError('patch side must be positive; got $patchPx');
  }

  final radius = regionDiameterPx / 2.0;
  final stride = patchPx * strideFraction;
  // A patch is inside the circle when its farthest corner is, which is its
  // half-diagonal from the centre, not its half-width.
  final inset = patchPx * math.sqrt(2.0) / 2.0;
  final limit = radius - inset;

  final offsets = <(double, double)>[];
  if (limit >= 0.0) {
    final steps = pythonFloorDivide(limit, stride).toInt();
    for (var row = -steps; row <= steps; row++) {
      for (var column = -steps; column <= steps; column++) {
        final dy = row * stride;
        final dx = column * stride;
        // CPython's `hypot` and this can differ in the last place; SPEC 0081
        // records the boundary and the golden keeps its cases away from it.
        if (math.sqrt(dy * dy + dx * dx) <= limit + 1e-9) {
          offsets.add((dy, dx));
        }
      }
    }
  }

  if (offsets.length < minPatches) {
    return (geometry: null, refusal: PatchRefusal.regionTooSmall);
  }
  offsets.sort((a, b) {
    final byRow = a.$1.compareTo(b.$1);
    return byRow != 0 ? byRow : a.$2.compareTo(b.$2);
  });
  return (
    geometry: PatchGeometry._(
      patchPx: patchPx,
      patchMm: patchPx * canonicalMmPerPx,
      stridePx: stride,
      insetPx: inset,
      regionRadiusPx: radius,
      offsets: List.unmodifiable(offsets),
    ),
    refusal: null,
  );
}

/// One pixel's grey level as `cut_patches` computes it: BT.601, rounded half
/// to even as numpy's `rint` does, clipped to a byte.
int greyOf(int red, int green, int blue) {
  final luma = lumaRed * red + lumaGreen * green + lumaBlue * blue;
  return _roundHalfEven(luma).clamp(0, 255);
}

/// Python's float floor division `a // b`, as CPython defines it.
///
/// It is not always `floor(a / b)`: `1 // 0.1` is 9, while `1 / 0.1` rounds to
/// exactly 10.
double pythonFloorDivide(double a, double b) {
  var mod = a.remainder(b);
  var div = (a - mod) / b;
  if (mod != 0.0 && (b < 0.0) != (mod < 0.0)) {
    mod += b;
    div -= 1.0;
  }
  if (div == 0.0) return (a / b).isNegative ? -0.0 : 0.0;
  var floor = div.floorToDouble();
  if (div - floor > 0.5) floor += 1.0;
  return floor;
}

/// Python's `round` and numpy's `rint`: to the nearest integer, and to the even
/// one on a tie. Dart's `round` breaks a tie away from zero instead, which
/// moves 13,178 of the 16.7 million RGB triples one grey level (ADR 0025).
int _roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final fraction = value - floor;
  final lower = floor.toInt();
  if (fraction > 0.5) return lower + 1;
  if (fraction < 0.5) return lower;
  return lower.isEven ? lower : lower + 1;
}

Uint8List _greyPlane(RgbFrame frame) {
  final rgb = frame.rgb;
  final grey = Uint8List(frame.width * frame.height);
  for (var pixel = 0; pixel < grey.length; pixel++) {
    grey[pixel] = greyOf(
      rgb[pixel * 3],
      rgb[pixel * 3 + 1],
      rgb[pixel * 3 + 2],
    );
  }
  return grey;
}

// --- Pillow 10.4 `BILINEAR`, from `libImaging/Resample.c` ---------------------

/// `PRECISION_BITS`: coefficients in fixed point, `32 - 8 - 2` bits.
const int _precisionBits = 22;

/// One axis's resampling taps: `precompute_coeffs` then `normalize_coeffs_8bpc`.
class _Taps {
  _Taps(this.size, this.first, this.count, this.weights);

  /// Taps per output position, the `ksize` stride into [weights].
  final int size;
  final Int32List first;
  final Int32List count;
  final Int32List weights;
}

double _bilinearFilter(double x) {
  if (x < 0.0) x = -x;
  if (x < 1.0) return 1.0 - x;
  return 0.0;
}

_Taps _taps(int inSize, int outSize) {
  // The box is the whole frame, so `in1 - in0` is `inSize`.
  final scale = inSize / outSize;
  var filterScale = scale;
  if (filterScale < 1.0) filterScale = 1.0;
  // BILINEAR's support is 1.0, widened by the reduction: the low-pass.
  final support = 1.0 * filterScale;
  final size = support.ceil() * 2 + 1;

  final first = Int32List(outSize);
  final count = Int32List(outSize);
  final weights = Int32List(outSize * size);
  final real = Float64List(size);
  for (var xx = 0; xx < outSize; xx++) {
    final center = (xx + 0.5) * scale;
    var total = 0.0;
    final ss = 1.0 / filterScale;
    // C's `(int)` truncates toward zero, as `toInt` does.
    var xmin = (center - support + 0.5).toInt();
    if (xmin < 0) xmin = 0;
    var xmax = (center + support + 0.5).toInt();
    if (xmax > inSize) xmax = inSize;
    xmax -= xmin;
    for (var x = 0; x < xmax; x++) {
      final w = _bilinearFilter((x + xmin - center + 0.5) * ss);
      real[x] = w;
      total += w;
    }
    for (var x = 0; x < xmax; x++) {
      if (total != 0.0) real[x] /= total;
    }
    for (var x = 0; x < xmax; x++) {
      final k = real[x];
      weights[xx * size + x] = k < 0
          ? (-0.5 + k * (1 << _precisionBits)).toInt()
          : (0.5 + k * (1 << _precisionBits)).toInt();
    }
    first[xx] = xmin;
    count[xx] = xmax;
  }
  return _Taps(size, first, count, weights);
}

/// `clip8`: the accumulator back to a byte.
int _clip8(int accumulator) {
  final value = accumulator >> _precisionBits;
  return value < 0 ? 0 : (value > 255 ? 255 : value);
}

/// `Image.resize(size, BILINEAR)` on an RGB image, byte for byte.
RgbFrame _resizeBilinear(RgbFrame frame, int width, int height) {
  // `Image.resize` copies rather than resamples when the size does not change.
  if (width == frame.width && height == frame.height) {
    return RgbFrame(width, height, Uint8List.fromList(frame.rgb));
  }
  var source = frame.rgb;
  var sourceWidth = frame.width;
  const rounding = 1 << (_precisionBits - 1);

  // Horizontal pass first, and only when the width changes, as
  // `ImagingResampleInner` does. It resamples every row; Pillow skips the rows
  // the vertical pass never reads, which changes no pixel.
  if (width != frame.width) {
    final taps = _taps(frame.width, width);
    final out = Uint8List(width * frame.height * 3);
    for (var y = 0; y < frame.height; y++) {
      final row = y * sourceWidth * 3;
      for (var xx = 0; xx < width; xx++) {
        var ss0 = rounding, ss1 = rounding, ss2 = rounding;
        final xmin = taps.first[xx];
        final base = xx * taps.size;
        for (var x = 0; x < taps.count[xx]; x++) {
          final k = taps.weights[base + x];
          final pixel = row + (x + xmin) * 3;
          ss0 += source[pixel] * k;
          ss1 += source[pixel + 1] * k;
          ss2 += source[pixel + 2] * k;
        }
        final target = (y * width + xx) * 3;
        out[target] = _clip8(ss0);
        out[target + 1] = _clip8(ss1);
        out[target + 2] = _clip8(ss2);
      }
    }
    source = out;
    sourceWidth = width;
  }

  if (height != frame.height) {
    final taps = _taps(frame.height, height);
    final out = Uint8List(sourceWidth * height * 3);
    for (var yy = 0; yy < height; yy++) {
      final ymin = taps.first[yy];
      final base = yy * taps.size;
      for (var xx = 0; xx < sourceWidth; xx++) {
        var ss0 = rounding, ss1 = rounding, ss2 = rounding;
        for (var y = 0; y < taps.count[yy]; y++) {
          final k = taps.weights[base + y];
          final pixel = ((y + ymin) * sourceWidth + xx) * 3;
          ss0 += source[pixel] * k;
          ss1 += source[pixel + 1] * k;
          ss2 += source[pixel + 2] * k;
        }
        final target = (yy * sourceWidth + xx) * 3;
        out[target] = _clip8(ss0);
        out[target + 1] = _clip8(ss1);
        out[target + 2] = _clip8(ss2);
      }
    }
    source = out;
  }
  return RgbFrame(width, height, source);
}
