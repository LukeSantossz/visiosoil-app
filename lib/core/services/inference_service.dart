import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../models/class_score.dart';
import 'classification_report.dart';
import 'descriptors/descriptor_contract.dart';
import 'descriptors/patch_descriptors.dart';
import 'descriptors/patch_grid.dart';
import 'descriptors/photograph_measurement.dart';

/// Result of soil texture classification inference.
class InferenceResult {
  final String textureClass;
  final double confidenceScore;

  /// Every class and its probability, highest first.
  ///
  /// [textureClass] and [confidenceScore] are the first entry's label and
  /// probability; they keep their names and meaning so existing call sites are
  /// untouched. Defaults to empty because callers that predate the distribution
  /// construct a result without one.
  final List<ClassScore> distribution;

  const InferenceResult({
    required this.textureClass,
    required this.confidenceScore,
    this.distribution = const [],
  });
}

/// Everything the inference isolate needs: the work to do, and the port to
/// answer on.
class InferenceRequest {
  /// Port the entry point sends its [ClassificationReport] back on. The
  /// isolate's exit is wired to it too, so a worker that dies before answering
  /// arrives as `null` rather than as silence.
  final SendPort responsePort;
  final String imagePath;

  /// Parsed once by [InferenceService.initialize], and copied into the isolate:
  /// it holds only lists, strings and numbers.
  final DescriptorContract contract;
  final PhotographMeasurer measurer;

  const InferenceRequest({
    required this.responsePort,
    required this.imagePath,
    required this.contract,
    required this.measurer,
  });
}

/// Signature of the inference isolate's entry point. Injected so tests can
/// drive the timeout and teardown paths without running the pipeline.
///
/// An implementation must be a top-level or static function: a closure
/// capturing local state cannot be sent to a spawned isolate.
typedef InferenceIsolateEntry = void Function(InferenceRequest request);

/// Signature for loading the contract asset as text. Injected so tests can
/// drive the initialization paths without the platform asset bundle.
typedef ContractAssetLoader = Future<String> Function(String key);

/// On-device soil texture classification by the descriptor path (ADR 0024,
/// SPEC 0083).
///
/// [initialize] reads the released contract. [classify] runs the photograph
/// through the path in an isolate so the main thread is never blocked: decode,
/// orient, measure, cut the canonical patch grid, describe each patch, and
/// score the patches with the contract.
class InferenceService {
  InferenceService({this.measurer = measurementUnavailable});

  /// The released contract (SPEC 0082, ADR 0012).
  static const String contractPath = 'assets/models/spec.json';

  /// What measures a photograph's scale and soil region. This build has none
  /// ([measurementUnavailable]); the A4-sheet reader supplies one.
  final PhotographMeasurer measurer;

  /// Maximum attempts to load the contract before giving up for the current
  /// call.
  static const int _maxInitAttempts = 3;

  /// Delay between initialization retries.
  static const Duration _initRetryDelay = Duration(milliseconds: 300);

  /// Maximum time to wait for the contract asset to load.
  static const Duration _contractLoadTimeout = Duration(seconds: 5);

  /// Maximum time to wait for a single classification before giving up.
  static const Duration _inferenceTimeout = Duration(seconds: 15);

  DescriptorContract? _contract;

  /// Set when the contract is malformed or unsupported: a build-time fact that
  /// retrying cannot fix, so further initialization attempts report it again.
  ClassificationFailureCause? _permanentCause;

  /// Indicates whether the service is ready for inference.
  bool get isReady => _contract != null;

  /// Initializes the service by loading and parsing the released contract.
  ///
  /// Returns `null` once the contract is parsed, and the cause otherwise, so
  /// no startup failure is flattened on its way to [classify].
  ///
  /// A contract that parses to a refusal is
  /// [ClassificationFailureCause.contractMalformed] or
  /// [ClassificationFailureCause.contractUnsupported], and is not reloaded. A
  /// loader that fails on every attempt is
  /// [ClassificationFailureCause.contractMissing]: no contract text was
  /// obtained. A later call may still retry that one.
  ///
  /// [assetLoader] and [retryDelay] are injectable for tests.
  Future<ClassificationFailureCause?> initialize({
    ContractAssetLoader? assetLoader,
    Duration retryDelay = _initRetryDelay,
  }) async {
    if (_contract != null) return null;
    if (_permanentCause != null) return _permanentCause;

    final load = assetLoader ?? rootBundle.loadString;

    for (var attempt = 1; attempt <= _maxInitAttempts; attempt++) {
      final String text;
      try {
        text = await load(contractPath).timeout(
          _contractLoadTimeout,
          onTimeout: () => throw Exception('Timeout loading the contract'),
        );
      } catch (e) {
        developer.log(
          'Failed to load the contract '
          '(attempt $attempt/$_maxInitAttempts): $e',
          name: 'InferenceService',
        );
        if (attempt < _maxInitAttempts) {
          await Future<void>.delayed(retryDelay);
        }
        continue;
      }
      final parsed = parseDescriptorContract(text);
      if (parsed.cause != null) {
        // A broken or unsupported contract will not change without a new
        // build: do not reload it.
        return _permanentCause = parsed.cause;
      }
      _contract = parsed.contract;
      return null;
    }

    // Attempts exhausted for this call; a later call may retry.
    return ClassificationFailureCause.contractMissing;
  }

  /// Runs soil texture classification on an image.
  ///
  /// [imagePath] is the absolute path of the image to classify. Always returns
  /// a report: the result when the run succeeded, the named cause otherwise.
  ///
  /// This is the single timeout governing a classification: callers await it
  /// rather than layering one of their own, because only this method holds the
  /// isolate handle and can therefore stop the work instead of abandoning it.
  ///
  /// [timeout] and [entryPoint] are injectable for tests.
  Future<ClassificationReport> classify(
    String imagePath, {
    Duration timeout = _inferenceTimeout,
    InferenceIsolateEntry entryPoint = _inferenceEntryPoint,
  }) async {
    if (!isReady) {
      final cause = await initialize();
      if (cause != null) return ClassificationReport.failed(cause);
    }

    // Spawned rather than `Isolate.run` so the timeout has a handle to kill.
    final responsePort = ReceivePort();
    Isolate? isolate;
    try {
      try {
        // The exit is sent to the same port, so a worker that dies before
        // answering is reported now rather than when the timeout fires.
        isolate = await Isolate.spawn(
          entryPoint,
          InferenceRequest(
            responsePort: responsePort.sendPort,
            imagePath: imagePath,
            contract: _contract!,
            measurer: measurer,
          ),
          onExit: responsePort.sendPort,
        );
      } catch (e) {
        developer.log(
          'classify() could not spawn: $e',
          name: 'InferenceService',
        );
        return const ClassificationReport.failed(
          ClassificationFailureCause.isolateFailure,
        );
      }

      final Object? message;
      try {
        message = await responsePort.first.timeout(timeout);
      } on TimeoutException {
        return const ClassificationReport.failed(
          ClassificationFailureCause.timeout,
        );
      }
      if (message is ClassificationReport) return message;
      // `null` is the exit notice: the worker ended without answering.
      return const ClassificationReport.failed(
        ClassificationFailureCause.isolateFailure,
      );
    } finally {
      // Releases the worker and the port on every path. On success the isolate
      // has already done its work; on timeout or error this is what stops it.
      isolate?.kill(priority: Isolate.immediate);
      responsePort.close();
    }
  }

  /// Entry point of the inference isolate: runs the work and answers on the
  /// request's port. Static so it can be sent to a spawned isolate.
  static Future<void> _inferenceEntryPoint(InferenceRequest request) async {
    final report = await runInference(
      request.imagePath,
      request.contract,
      request.measurer,
    );
    request.responsePort.send(report);
  }

  /// Runs the descriptor path (called inside the isolate). Each stage reports
  /// its own cause: the image, the measurement, the grid, then the score.
  @visibleForTesting
  static Future<ClassificationReport> runInference(
    String imagePath,
    DescriptorContract contract,
    PhotographMeasurer measurer,
  ) async {
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      return const ClassificationReport.failed(
        ClassificationFailureCause.imageMissing,
      );
    }

    img.Image? image;
    try {
      image = img.decodeImage(imageFile.readAsBytesSync());
    } catch (e) {
      developer.log('decode failed: $e', name: 'InferenceService');
    }
    if (image == null) {
      return const ClassificationReport.failed(
        ClassificationFailureCause.imageUndecodable,
      );
    }

    try {
      // Orientation first, as `ImageOps.exif_transpose` is in Python: the
      // measurement and the grid are in the displayed frame.
      final frame = frameOf(img.bakeOrientation(image));

      final measured = measurer(frame);
      final measurement = measured.measurement;
      if (measurement == null) {
        return ClassificationReport.failed(
          measured.cause ?? ClassificationFailureCause.computationError,
        );
      }

      final cut = canonicalPatches(
        measurement.frame,
        measuredMmPerPx: measurement.mmPerPx,
        centreYPx: measurement.centreYPx,
        centreXPx: measurement.centreXPx,
        diameterPx: measurement.diameterPx,
        canonicalMmPerPx: contract.canonicalMmPerPx,
        patchPx: contract.patchPx,
        strideFraction: contract.patchStrideFraction,
        minPatches: contract.minPatches,
      );
      final patches = cut.patches;
      if (patches == null) {
        return ClassificationReport.failed(_causeOf(cut.refusal!));
      }

      final features = [
        for (final patch in patches)
          describePatch(patch, contract.patchPx, contract.patchPx),
      ];
      final Float64List probabilities;
      try {
        probabilities = contract.distribution(features);
      } on ArgumentError catch (e) {
        // A non-finite logit: the contract cannot score these patches.
        developer.log('distribution refused: $e', name: 'InferenceService');
        return const ClassificationReport.failed(
          ClassificationFailureCause.outputInvalid,
        );
      }
      return reportFor(probabilities, contract.classes);
    } catch (e) {
      developer.log(
        'InferenceService.runInference failed: $e',
        name: 'InferenceService',
      );
      return const ClassificationReport.failed(
        ClassificationFailureCause.computationError,
      );
    }
  }

  /// A decoded image as the interleaved RGB bytes the patch grid reads. Alpha
  /// is dropped rather than composited, as Pillow's `convert("RGB")` does.
  @visibleForTesting
  static RgbFrame frameOf(img.Image image) {
    final rgb = image.convert(format: img.Format.uint8, numChannels: 3);
    return RgbFrame(
      rgb.width,
      rgb.height,
      Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb)),
    );
  }

  static ClassificationFailureCause _causeOf(PatchRefusal refusal) =>
      switch (refusal) {
        PatchRefusal.tooCoarse =>
          ClassificationFailureCause.photographTooCoarse,
        PatchRefusal.regionTooSmall =>
          ClassificationFailureCause.soilRegionTooSmall,
        PatchRefusal.outsideFrame =>
          ClassificationFailureCause.soilRegionOutsideFrame,
      };

  /// The report for one distribution over [labels]: invalid output when it
  /// does not carry one probability per label, and the result otherwise.
  @visibleForTesting
  static ClassificationReport reportFor(
    List<double> probabilities,
    List<String> labels,
  ) {
    final distribution = buildDistribution(probabilities, labels);
    if (distribution == null) {
      return const ClassificationReport.failed(
        ClassificationFailureCause.outputInvalid,
      );
    }
    // Top-1 comes from the distribution, so `distribution.first` and these two
    // fields cannot disagree.
    return ClassificationReport.ok(
      InferenceResult(
        textureClass: distribution.first.label,
        confidenceScore: distribution.first.probability,
        distribution: distribution,
      ),
    );
  }

  /// Builds the full distribution over [labels], highest probability first, or
  /// null when it does not carry one probability per label.
  ///
  /// Probabilities are passed through verbatim. Renormalising them would hide
  /// a contract that scores wrongly, and would make every verdict threshold
  /// meaningless while looking correct.
  ///
  /// Ties break on the order of [labels], which is the contract's. Probability
  /// alone does not order the distribution — two classes can hold the same
  /// value — and the order is user-visible, because it decides which class is
  /// named as top-1 and which pair an ambiguous verdict puts on screen.
  @visibleForTesting
  static List<ClassScore>? buildDistribution(
    List<double> probabilities,
    List<String> labels,
  ) {
    if (probabilities.length != labels.length) return null;
    // A NaN sorts above every number under `compareTo`, so it would become the
    // top-1 class and carry a NaN confidence into the result, and a finite
    // value outside the unit interval would clear every verdict threshold.
    // Refuse rather than fabricate a plausible-looking result.
    if (probabilities.any(
      (probability) => !ClassScore.isProbability(probability),
    )) {
      return null;
    }

    final scores = <ClassScore>[
      for (var index = 0; index < labels.length; index++)
        ClassScore(label: labels[index], probability: probabilities[index]),
    ];
    scores.sort((first, second) {
      final byProbability = second.probability.compareTo(first.probability);
      if (byProbability != 0) return byProbability;
      return labels
          .indexOf(first.label)
          .compareTo(labels.indexOf(second.label));
    });
    return List.unmodifiable(scores);
  }

  /// Releases the service's resources.
  void dispose() {
    _contract = null;
    _permanentCause = null;
  }
}
