/// The descriptor contract: the numbers a fitted descriptor pipeline is, and
/// the arithmetic that turns patch features into a class distribution
/// (SPEC 0079, ADR 0024).
///
/// `ml/src/contract.py` writes the schema and this file reads it. The two agree
/// by construction of `test/fixtures/contract/golden.json`.
///
/// A contract that is broken is `contractMalformed`. One that is well formed and
/// describes something this build does not compute is `contractUnsupported` —
/// in particular, descriptors defined differently from `patch_descriptors.dart`,
/// which would still produce plausible numbers.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../classification_report.dart';
import 'patch_descriptors.dart';

/// The schema version this reader implements. Version 1 was SPEC 0035's network
/// contract, which never shipped.
const int descriptorContractVersion = 2;

const String _classifier = 'descriptors';
const String _aggregation = 'mean';
const String _lbpMapping = 'rotation_invariant_uniform';

/// The LBP ring [lbpNeighbours] reads: the eight adjacent pixels.
final int _lbpRadius = lbpNeighbours
    .map((offset) => math.max(offset.$1.abs(), offset.$2.abs()))
    .reduce(math.max);

/// A parsed, validated descriptor contract.
class DescriptorContract {
  DescriptorContract._({
    required this.modelVersion,
    required this.datasetVersion,
    required this.classes,
    required this.canonicalMmPerPx,
    required this.patchPx,
    required this.patchStrideFraction,
    required this.minPatches,
    required this.mean,
    required this.scale,
    required this.coefficients,
    required this.intercepts,
  });

  final String modelVersion;
  final String datasetVersion;

  /// The class labels, in the regression's output order.
  final List<String> classes;

  final double canonicalMmPerPx;
  final int patchPx;
  final double patchStrideFraction;
  final int minPatches;

  final Float64List mean;
  final Float64List scale;

  /// One row per class, over the features in [descriptorFeatureNames] order.
  final List<Float64List> coefficients;
  final Float64List intercepts;

  /// The class distribution of one photograph: each patch standardised, scored
  /// by the regression and turned into probabilities by a softmax, then the
  /// mean over the patches. This is `predict_proba` then `arms.probe._predict`'s
  /// mean.
  ///
  /// Throws an [ArgumentError] for a photograph with no patch, or for a patch
  /// that does not carry one value per feature.
  Float64List distribution(List<Float64List> patches) {
    if (patches.isEmpty) {
      throw ArgumentError('a photograph with no patch has no distribution');
    }
    final width = mean.length;
    final total = Float64List(classes.length);
    final logits = Float64List(classes.length);
    final standardised = Float64List(width);
    for (final patch in patches) {
      if (patch.length != width) {
        throw ArgumentError(
          'a patch carries $width features; got ${patch.length}',
        );
      }
      for (var feature = 0; feature < width; feature++) {
        standardised[feature] = (patch[feature] - mean[feature]) / scale[feature];
      }
      var largest = double.negativeInfinity;
      for (var index = 0; index < classes.length; index++) {
        final row = coefficients[index];
        var logit = intercepts[index];
        for (var feature = 0; feature < width; feature++) {
          logit += row[feature] * standardised[feature];
        }
        logits[index] = logit;
        largest = math.max(largest, logit);
      }
      // Softmax after subtracting the largest logit, so no exponential
      // overflows.
      var sum = 0.0;
      for (var index = 0; index < classes.length; index++) {
        logits[index] = math.exp(logits[index] - largest);
        sum += logits[index];
      }
      for (var index = 0; index < classes.length; index++) {
        total[index] += logits[index] / sum;
      }
    }
    for (var index = 0; index < classes.length; index++) {
      total[index] /= patches.length;
    }
    return total;
  }
}

/// Parses [text] as a descriptor contract: the contract, or the cause it was
/// refused with. Never throws.
({DescriptorContract? contract, ClassificationFailureCause? cause})
    parseDescriptorContract(String text) {
  try {
    return (contract: _parse(text), cause: null);
  } on _Refusal catch (refusal) {
    return (contract: null, cause: refusal.cause);
  }
}

class _Refusal implements Exception {
  const _Refusal(this.cause, this.reason);

  final ClassificationFailureCause cause;
  final String reason;

  @override
  String toString() => '${cause.name}: $reason';
}

Never _malformed(String reason) =>
    throw _Refusal(ClassificationFailureCause.contractMalformed, reason);

Never _unsupported(String reason) =>
    throw _Refusal(ClassificationFailureCause.contractUnsupported, reason);

DescriptorContract _parse(String text) {
  final Object? document;
  try {
    document = jsonDecode(text);
  } on FormatException catch (error) {
    _malformed('not JSON: ${error.message}');
  }
  if (document is! Map<String, dynamic>) _malformed('not a JSON object');

  // The version and the classifier first: a contract written to another schema
  // is unsupported, whatever else it holds.
  final version = _int(document, 'spec_version');
  if (version != descriptorContractVersion) {
    _unsupported('spec_version $version; this reader implements '
        '$descriptorContractVersion');
  }
  final classifier = _string(document, 'classifier');
  if (classifier != _classifier) _unsupported('classifier $classifier');

  final modelVersion = _string(document, 'model_version');
  final datasetVersion = _string(document, 'dataset_version');

  final classes = _list(document, 'classes')
      .map((value) => value is String ? value : _malformed('a class label'))
      .toList();
  if (classes.isEmpty) _malformed('no class');
  if (classes.toSet().length != classes.length) _malformed('a repeated class');

  final geometry = _map(document, 'geometry');
  final canonicalMmPerPx = _double(geometry, 'canonical_mm_per_px');
  final patchPx = _int(geometry, 'patch_px');
  final patchStrideFraction = _double(geometry, 'patch_stride_fraction');
  final minPatches = _int(geometry, 'min_patches');
  if (canonicalMmPerPx <= 0 ||
      patchPx <= 0 ||
      patchStrideFraction <= 0 ||
      patchStrideFraction > 1 ||
      minPatches < 1) {
    _malformed('geometry out of range');
  }

  final descriptors = _map(document, 'descriptors');
  final glcmLevelsRead = _int(descriptors, 'glcm_levels');
  final glcmOffsetsRead = _list(descriptors, 'glcm_offsets').map((offset) {
    if (offset is! List || offset.length != 2 || offset.any((v) => v is! int)) {
      _malformed('a GLCM offset');
    }
    return (offset[0] as int, offset[1] as int);
  }).toList();
  final lbpPointsRead = _int(descriptors, 'lbp_points');
  final lbpRadiusRead = _int(descriptors, 'lbp_radius');
  final lbpMappingRead = _string(descriptors, 'lbp_mapping');
  final spectralBandsRead = _int(descriptors, 'spectral_bands');
  final minCyclesRead = _double(descriptors, 'min_cycles_per_patch');
  final features = _list(descriptors, 'features')
      .map((value) => value is String ? value : _malformed('a feature name'))
      .toList();

  final standardiser = _map(document, 'standardiser');
  final mean = _doubles(standardiser, 'mean');
  final scale = _doubles(standardiser, 'scale');
  final regression = _map(document, 'regression');
  final coefficients = _list(regression, 'coefficients').map((row) {
    if (row is! List) _malformed('a coefficient row');
    return _finite(row, 'a coefficient row');
  }).toList();
  final intercepts = _doubles(regression, 'intercepts');
  final aggregation = _string(document, 'aggregation');

  // Lengths, against the feature list and the class list.
  if (mean.length != features.length || scale.length != features.length) {
    _malformed('the standardiser does not carry one value per feature');
  }
  if (scale.any((value) => value <= 0)) _malformed('a scale of zero or below');
  if (coefficients.length != classes.length ||
      intercepts.length != classes.length) {
    _malformed('the regression does not carry one row per class');
  }
  if (coefficients.any((row) => row.length != features.length)) {
    _malformed('a coefficient row does not carry one value per feature');
  }

  // Well formed. Now whether it describes what this build computes.
  if (aggregation != _aggregation) _unsupported('aggregation $aggregation');
  final offsetsAgree = glcmOffsetsRead.length == glcmOffsets.length &&
      [
        for (var i = 0; i < glcmOffsets.length; i++)
          glcmOffsetsRead[i] == glcmOffsets[i],
      ].every((agrees) => agrees);
  if (glcmLevelsRead != glcmLevels ||
      !offsetsAgree ||
      lbpPointsRead != lbpPoints ||
      lbpRadiusRead != _lbpRadius ||
      lbpMappingRead != _lbpMapping ||
      spectralBandsRead != spectralBands ||
      minCyclesRead != minCyclesPerPatch) {
    _unsupported('a descriptor fixed point differs from patch_descriptors');
  }
  final featuresAgree = features.length == descriptorFeatureNames.length &&
      [
        for (var i = 0; i < features.length; i++)
          features[i] == descriptorFeatureNames[i],
      ].every((agrees) => agrees);
  if (!featuresAgree) {
    _unsupported('the feature list is not descriptorFeatureNames in order');
  }

  return DescriptorContract._(
    modelVersion: modelVersion,
    datasetVersion: datasetVersion,
    classes: List.unmodifiable(classes),
    canonicalMmPerPx: canonicalMmPerPx,
    patchPx: patchPx,
    patchStrideFraction: patchStrideFraction,
    minPatches: minPatches,
    mean: mean,
    scale: scale,
    coefficients: List.unmodifiable(coefficients),
    intercepts: intercepts,
  );
}

Object? _field(Map<String, dynamic> map, String key) =>
    map.containsKey(key) ? map[key] : _malformed('no $key');

Map<String, dynamic> _map(Map<String, dynamic> map, String key) {
  final value = _field(map, key);
  return value is Map<String, dynamic> ? value : _malformed('$key: an object');
}

List<dynamic> _list(Map<String, dynamic> map, String key) {
  final value = _field(map, key);
  return value is List ? value : _malformed('$key: a list');
}

String _string(Map<String, dynamic> map, String key) {
  final value = _field(map, key);
  return value is String ? value : _malformed('$key: a string');
}

int _int(Map<String, dynamic> map, String key) {
  final value = _field(map, key);
  return value is int ? value : _malformed('$key: an integer');
}

double _double(Map<String, dynamic> map, String key) {
  final value = _field(map, key);
  if (value is! num || !value.isFinite) _malformed('$key: a finite number');
  return value.toDouble();
}

Float64List _doubles(Map<String, dynamic> map, String key) =>
    _finite(_list(map, key), key);

Float64List _finite(List<dynamic> values, String what) {
  final result = Float64List(values.length);
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (value is! num || !value.isFinite) _malformed('$what: a finite number');
    result[index] = value.toDouble();
  }
  return result;
}
