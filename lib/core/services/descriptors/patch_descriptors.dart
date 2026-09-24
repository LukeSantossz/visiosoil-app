/// Classical texture descriptors over one greyscale patch — the Dart half
/// (SPEC 0077, ADR 0024).
///
/// A port, number for number, of `ml/src/descriptors.py`. The two agree by
/// construction of `test/fixtures/descriptors/golden.json`, and a divergence
/// fails both suites. Where this file and the Python differ in how a number is
/// computed, the comment says why the answer does not.
///
/// Four component groups over a scale-normalised patch of ADR 0018: 4
/// first-order moments, 8 log-spaced spectral bands, 10 rotation-invariant
/// uniform LBP bins and 4 co-occurrence statistics, 26 features in the order of
/// [descriptorFeatureNames].
///
/// Everything here is pure arithmetic over pixels: no model, no I/O, no
/// Flutter, no randomness.
library;

import 'dart:math' as math;
import 'dart:typed_data';

// --- fixed points of the descriptors ----------------------------------------
// Not tunable: SPEC 0054 fixed them before the E0 run, and changing one changes
// what the classifier measures. Each is named after its Python counterpart.

/// Grey levels the co-occurrence matrix is built over, by integer division of
/// the fixed 0-255 range.
const int glcmLevels = 16;
const int glcmBinWidth = 256 ~/ glcmLevels;

/// 0, 45, 90 and 135 degrees at one step, as `(dy, dx)`, rows downward.
const List<(int, int)> glcmOffsets = [(0, 1), (-1, 1), (-1, 0), (-1, -1)];

/// Neighbours compared with the centre, anticlockwise from east; bit `i` of an
/// LBP code is neighbour `i`.
const List<(int, int)> lbpNeighbours = [
  (0, 1),
  (-1, 1),
  (-1, 0),
  (-1, -1),
  (0, -1),
  (1, -1),
  (1, 0),
  (1, 1),
];
const int lbpPoints = 8;
const int lbpBins = lbpPoints + 2;

/// Radial spatial-frequency bands, log-spaced from [minCyclesPerPatch] to the
/// Nyquist radius.
const int spectralBands = 8;
const double minCyclesPerPatch = 2.0;

/// A 3x3 neighbourhood needs one: below it there is no interior pixel and no
/// co-occurring pair.
const int minSidePx = 3;

/// A radius this close to a band edge is on it, and goes to the upper band.
/// Exact ties are structural — a square patch's middle edge is the square root
/// of its side, and `160 = 12² + 4²` — and numpy computes that edge a few units
/// in the last place off, so a raw comparison would be decided by rounding
/// (SPEC 0077). The golden asserts this rule reproduces the reference's map.
const double _tie = 1e-9;

/// Every feature, by group and in output order, as
/// `src.descriptors.feature_names()` names them.
const List<String> descriptorFeatureNames = [
  'first_order.mean',
  'first_order.std',
  'first_order.skewness',
  'first_order.kurtosis',
  'spectral.band_0',
  'spectral.band_1',
  'spectral.band_2',
  'spectral.band_3',
  'spectral.band_4',
  'spectral.band_5',
  'spectral.band_6',
  'spectral.band_7',
  'lbp.uniform_0',
  'lbp.uniform_1',
  'lbp.uniform_2',
  'lbp.uniform_3',
  'lbp.uniform_4',
  'lbp.uniform_5',
  'lbp.uniform_6',
  'lbp.uniform_7',
  'lbp.uniform_8',
  'lbp.non_uniform',
  'glcm.contrast',
  'glcm.homogeneity',
  'glcm.energy',
  'glcm.correlation',
];

/// Describe one greyscale patch as the 26 features of
/// [descriptorFeatureNames].
///
/// [pixels] is the single grey plane, `height × width` values in row-major
/// order. Choosing that plane from a photograph is the caller's job.
///
/// Throws an [ArgumentError] if [pixels] is not `height × width` long, if a side
/// is below [minSidePx], or if the patch is too small to reach the lowest
/// spectral band.
Float64List describePatch(Uint8List pixels, int height, int width) {
  if (pixels.length != height * width) {
    throw ArgumentError(
      'a ${height}x$width patch has ${height * width} pixels; '
      'got ${pixels.length}',
    );
  }
  if (math.min(height, width) < minSidePx) {
    throw ArgumentError(
      'a patch of ${height}x$width px has no interior pixel and no pair to '
      'describe; the floor is $minSidePx a side',
    );
  }
  final geometry = _geometry(height, width);

  final features = Float64List(descriptorFeatureNames.length);
  features.setRange(0, 4, _firstOrder(pixels));
  features.setRange(4, 12, _spectral(pixels, height, width, geometry));
  features.setRange(12, 22, _lbp(pixels, height, width));
  features.setRange(22, 26, _glcm(pixels, height, width));
  return features;
}

/// The nine band edges for one patch shape, as `numpy.geomspace` spaces them.
///
/// Throws an [ArgumentError] if the shape resolves no band.
Float64List descriptorBandEdges(int height, int width) =>
    Float64List.fromList(_geometry(height, width).edges);

/// The band of every frequency bin of one shape, in `numpy.fft.fftfreq` order
/// and row-major, with -1 for a bin in no band.
///
/// Throws an [ArgumentError] if the shape resolves no band.
Int8List descriptorBandMap(int height, int width) =>
    Int8List.fromList(_geometry(height, width).bands);

// --- first order -------------------------------------------------------------

Float64List _firstOrder(Uint8List pixels) {
  final count = pixels.length;
  var sum = 0.0;
  for (final value in pixels) {
    sum += value;
  }
  final mean = sum / count;

  var second = 0.0;
  var third = 0.0;
  var fourth = 0.0;
  for (final value in pixels) {
    final centred = value - mean;
    final squared = centred * centred;
    second += squared;
    third += squared * centred;
    fourth += squared * squared;
  }
  final deviation = math.sqrt(second / count);
  if (deviation <= 0.0) {
    // One grey level has no shape to report; zero is the neutral value of both
    // moments and, unlike 0/0, a number.
    return Float64List.fromList([mean, 0.0, 0.0, 0.0]);
  }
  final skewness = (third / count) / math.pow(deviation, 3);
  final kurtosis = (fourth / count) / math.pow(deviation, 4) - 3.0;
  return Float64List.fromList([mean, deviation, skewness, kurtosis]);
}

// --- spectral ----------------------------------------------------------------

Float64List _spectral(
  Uint8List pixels,
  int height,
  int width,
  _Geometry geometry,
) {
  final energy = _radialBandEnergy(pixels, height, width, geometry);
  var total = 0.0;
  for (final value in energy) {
    total += value;
  }
  if (total <= 0.0) {
    // No structure, so no distribution over bands.
    return Float64List(spectralBands);
  }
  for (var band = 0; band < spectralBands; band++) {
    energy[band] /= total;
  }
  return energy;
}

/// Unnormalised power summed over each band, by a separable direct DFT.
///
/// 160 is `2^5 × 5`, so a radix-2 FFT does not apply. A direct DFT is plain sums
/// against one twiddle table, and its error does not compound through stages
/// (SPEC 0077). The mean is subtracted first: that changes only the
/// zero-frequency coefficient, which no band holds, and it makes a flat patch
/// exactly zero everywhere, as numpy's FFT does, rather than leaving rounding
/// noise the normalisation would turn into a distribution.
Float64List _radialBandEnergy(
  Uint8List pixels,
  int height,
  int width,
  _Geometry geometry,
) {
  var sum = 0.0;
  for (final value in pixels) {
    sum += value;
  }
  final mean = sum / pixels.length;

  // Rows first: rowRe/rowIm[y * width + kx].
  final rowRe = Float64List(height * width);
  final rowIm = Float64List(height * width);
  final cosW = geometry.cosWidth;
  final sinW = geometry.sinWidth;
  final centred = Float64List(width);
  for (var y = 0; y < height; y++) {
    final offset = y * width;
    for (var x = 0; x < width; x++) {
      centred[x] = pixels[offset + x] - mean;
    }
    for (var kx = 0; kx < width; kx++) {
      var re = 0.0;
      var im = 0.0;
      var index = 0;
      for (var x = 0; x < width; x++) {
        final value = centred[x];
        re += value * cosW[index];
        im -= value * sinW[index];
        index += kx;
        if (index >= width) index -= width;
      }
      rowRe[offset + kx] = re;
      rowIm[offset + kx] = im;
    }
  }

  // Then columns, accumulating each bin's power straight into its band.
  final energy = Float64List(spectralBands);
  final cosH = geometry.cosHeight;
  final sinH = geometry.sinHeight;
  final bands = geometry.bands;
  for (var kx = 0; kx < width; kx++) {
    for (var ky = 0; ky < height; ky++) {
      final band = bands[ky * width + kx];
      if (band < 0) continue;
      var re = 0.0;
      var im = 0.0;
      var index = 0;
      for (var y = 0; y < height; y++) {
        final a = rowRe[y * width + kx];
        final b = rowIm[y * width + kx];
        final c = cosH[index];
        final s = sinH[index];
        // (a + ib)(c - is)
        re += a * c + b * s;
        im += b * c - a * s;
        index += ky;
        if (index >= height) index -= height;
      }
      energy[band] += re * re + im * im;
    }
  }
  return energy;
}

/// What the spectral group needs for one shape, computed once per shape.
class _Geometry {
  _Geometry(this.edges, this.bands, this.cosHeight, this.sinHeight,
      this.cosWidth, this.sinWidth);

  final List<double> edges;
  final Int8List bands;
  final Float64List cosHeight;
  final Float64List sinHeight;
  final Float64List cosWidth;
  final Float64List sinWidth;
}

final Map<(int, int), _Geometry> _geometries = {};

_Geometry _geometry(int height, int width) =>
    _geometries[(height, width)] ??= _buildGeometry(height, width);

_Geometry _buildGeometry(int height, int width) {
  final nyquist = math.min(height, width) / 2.0;
  if (nyquist <= minCyclesPerPatch) {
    throw ArgumentError(
      'a ${height}x$width px patch resolves $nyquist cycles across itself and '
      'the lowest spectral band starts at $minCyclesPerPatch; there is no band '
      'to measure',
    );
  }

  // numpy's geomspace: log-spaced, with both ends exact.
  final edges = List<double>.generate(spectralBands + 1, (index) {
    if (index == 0) return minCyclesPerPatch;
    if (index == spectralBands) return nyquist;
    return minCyclesPerPatch *
        math.pow(nyquist / minCyclesPerPatch, index / spectralBands);
  });

  final bands = Int8List(height * width);
  for (var ky = 0; ky < height; ky++) {
    final fy = _frequency(ky, height);
    for (var kx = 0; kx < width; kx++) {
      final fx = _frequency(kx, width);
      final radius = math.sqrt((fy * fy + fx * fx).toDouble());
      var band = -1;
      for (var candidate = 0; candidate < spectralBands; candidate++) {
        if (radius >= edges[candidate] - _tie) band = candidate;
      }
      // Past the Nyquist radius only the corner directions are represented.
      if (radius > edges[spectralBands] + _tie) band = -1;
      bands[ky * width + kx] = band;
    }
  }

  (Float64List, Float64List) twiddles(int length) {
    final cos = Float64List(length);
    final sin = Float64List(length);
    for (var index = 0; index < length; index++) {
      final angle = 2 * math.pi * index / length;
      cos[index] = math.cos(angle);
      sin[index] = math.sin(angle);
    }
    return (cos, sin);
  }

  final (cosHeight, sinHeight) = twiddles(height);
  final (cosWidth, sinWidth) = twiddles(width);
  return _Geometry(edges, bands, cosHeight, sinHeight, cosWidth, sinWidth);
}

/// `numpy.fft.fftfreq(n)[index] * n`: cycles across the patch.
int _frequency(int index, int length) =>
    index <= (length - 1) ~/ 2 ? index : index - length;

// --- local binary patterns ---------------------------------------------------

Float64List _lbp(Uint8List pixels, int height, int width) {
  final binOfCode = _lbpBinOfCode;
  final counts = Float64List(lbpBins);
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final centre = pixels[y * width + x];
      var code = 0;
      for (var bit = 0; bit < lbpPoints; bit++) {
        final (dy, dx) = lbpNeighbours[bit];
        // A tie counts as a rise.
        if (pixels[(y + dy) * width + x + dx] >= centre) code |= 1 << bit;
      }
      counts[binOfCode[code]] += 1;
    }
  }
  final interior = (height - 2) * (width - 2);
  for (var bin = 0; bin < lbpBins; bin++) {
    counts[bin] /= interior;
  }
  return counts;
}

/// The rotation-invariant uniform mapping over all 256 codes: the number of ones
/// for a code with at most two circular transitions, the last bin otherwise.
final Uint8List _lbpBinOfCode = () {
  final table = Uint8List(1 << lbpPoints);
  for (var code = 0; code < table.length; code++) {
    var ones = 0;
    var transitions = 0;
    for (var position = 0; position < lbpPoints; position++) {
      final bit = (code >> position) & 1;
      final next = (code >> ((position + 1) % lbpPoints)) & 1;
      ones += bit;
      if (bit != next) transitions++;
    }
    table[code] = transitions <= 2 ? ones : lbpBins - 1;
  }
  return table;
}();

// --- grey-level co-occurrence ------------------------------------------------

Float64List _glcm(Uint8List pixels, int height, int width) {
  final levels = Uint8List(pixels.length);
  for (var index = 0; index < pixels.length; index++) {
    levels[index] = pixels[index] ~/ glcmBinWidth;
  }
  final total = Float64List(4);
  for (final offset in glcmOffsets) {
    final features = _glcmFeatures(_cooccurrence(levels, height, width, offset));
    for (var index = 0; index < 4; index++) {
      total[index] += features[index];
    }
  }
  for (var index = 0; index < 4; index++) {
    total[index] /= glcmOffsets.length;
  }
  return total;
}

/// Symmetric counts of the level pairs one [offset] apart.
Int64List _cooccurrence(
  Uint8List levels,
  int height,
  int width,
  (int, int) offset,
) {
  final (dy, dx) = offset;
  final counts = Int64List(glcmLevels * glcmLevels);
  final rowStart = math.max(0, -dy);
  final rowStop = height - math.max(0, dy);
  final columnStart = math.max(0, -dx);
  final columnStop = width - math.max(0, dx);
  for (var y = rowStart; y < rowStop; y++) {
    for (var x = columnStart; x < columnStop; x++) {
      final first = levels[y * width + x];
      final second = levels[(y + dy) * width + x + dx];
      counts[first * glcmLevels + second]++;
      counts[second * glcmLevels + first]++;
    }
  }
  return counts;
}

/// Contrast, homogeneity, energy (the angular second moment) and correlation of
/// one co-occurrence matrix.
List<double> _glcmFeatures(Int64List matrix) {
  var sum = 0;
  for (final count in matrix) {
    sum += count;
  }
  var contrast = 0.0;
  var homogeneity = 0.0;
  var energy = 0.0;
  final marginal = Float64List(glcmLevels);
  for (var i = 0; i < glcmLevels; i++) {
    for (var j = 0; j < glcmLevels; j++) {
      final probability = matrix[i * glcmLevels + j] / sum;
      final squared = ((i - j) * (i - j)).toDouble();
      contrast += probability * squared;
      homogeneity += probability / (1.0 + squared);
      energy += probability * probability;
      marginal[i] += probability;
    }
  }

  var mean = 0.0;
  for (var i = 0; i < glcmLevels; i++) {
    mean += marginal[i] * i;
  }
  var variance = 0.0;
  for (var i = 0; i < glcmLevels; i++) {
    variance += marginal[i] * (i - mean) * (i - mean);
  }

  final double correlation;
  if (variance <= 0.0) {
    // One grey level: every pair is identical, and the limit is 1.
    correlation = 1.0;
  } else {
    var covariance = 0.0;
    for (var i = 0; i < glcmLevels; i++) {
      for (var j = 0; j < glcmLevels; j++) {
        covariance +=
            (matrix[i * glcmLevels + j] / sum) * (i - mean) * (j - mean);
      }
    }
    // Symmetric, so both marginals are one distribution.
    correlation = covariance / variance;
  }
  return [contrast, homogeneity, energy, correlation];
}
