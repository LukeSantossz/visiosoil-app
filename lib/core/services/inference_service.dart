import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../models/class_score.dart';
import '../../models/soil_texture_labels.dart';
import 'classification_report.dart';

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
  final Uint8List modelBytes;

  const InferenceRequest({
    required this.responsePort,
    required this.imagePath,
    required this.modelBytes,
  });
}

/// Signature of the inference isolate's entry point. Injected so tests can
/// drive the timeout and teardown paths without a real TFLite model.
///
/// An implementation must be a top-level or static function: a closure
/// capturing local state cannot be sent to a spawned isolate.
typedef InferenceIsolateEntry = void Function(InferenceRequest request);

/// Signature for loading the model asset. Injected so tests can drive the
/// initialization retry logic without the platform asset bundle.
typedef ModelAssetLoader = Future<ByteData> Function(String key);

/// TensorFlow Lite inference service for soil texture classification.
///
/// Loads the model from assets, preprocesses images, and runs inference
/// on-device. Inference is executed in an isolate to avoid blocking the main
/// thread.
class InferenceService {
  static const String _modelPath = 'assets/models/soil_classifier.tflite';

  /// Model input dimension (224x224 RGB).
  static const int _inputSize = 224;

  /// Soil texture classes aligned with ml/config.yaml, in model output order.
  ///
  /// Declared once in [SoilTextureLabels] and referenced here rather than
  /// copied, so a second declaration cannot drift out of step with this one.
  /// Public only so a test can assert that single source directly, matching
  /// how [buildDistribution] is widened.
  @visibleForTesting
  static const List<String> textureLabels = SoilTextureLabels.ordered;

  /// Maximum attempts to load the model before giving up for the current call.
  static const int _maxInitAttempts = 3;

  /// Delay between initialization retries.
  static const Duration _initRetryDelay = Duration(milliseconds: 300);

  /// Maximum time to wait for the model asset to load.
  static const Duration _modelLoadTimeout = Duration(seconds: 5);

  /// Maximum time to wait for a single inference run before giving up.
  static const Duration _inferenceTimeout = Duration(seconds: 15);

  Uint8List? _modelBytes;
  bool _isInitialized = false;

  /// Set when the model asset is empty — a build-time fact that retrying cannot
  /// fix, so further initialization attempts are skipped and report it again.
  ClassificationFailureCause? _permanentCause;

  /// Indicates whether the service is ready for inference.
  bool get isReady => _isInitialized && _modelBytes != null;

  /// Initializes the service by loading the model from assets.
  ///
  /// Returns `null` once the model bytes are loaded, and the cause otherwise,
  /// so no startup failure is flattened on its way to [classify]. The model is
  /// loaded as bytes so it can be passed to the isolate.
  ///
  /// An empty asset is [ClassificationFailureCause.modelEmpty] and is not
  /// retried. A loader that fails on every attempt is
  /// [ClassificationFailureCause.modelMissing]: no model bytes were obtained. A
  /// later call may still retry it, since a failed load is not always a missing
  /// file, and none of ADR 0015's causes names a transient one (SPEC 0078).
  ///
  /// [assetLoader] and [retryDelay] are injectable for tests.
  Future<ClassificationFailureCause?> initialize({
    ModelAssetLoader? assetLoader,
    Duration retryDelay = _initRetryDelay,
  }) async {
    if (_isInitialized) return null;
    if (_permanentCause != null) return _permanentCause;

    final load = assetLoader ?? rootBundle.load;

    for (var attempt = 1; attempt <= _maxInitAttempts; attempt++) {
      try {
        final byteData = await load(_modelPath).timeout(
          _modelLoadTimeout,
          onTimeout: () => throw Exception('Timeout loading model'),
        );
        if (byteData.lengthInBytes == 0) {
          // An empty model will not change without a new build: do not retry.
          return _permanentCause = ClassificationFailureCause.modelEmpty;
        }
        _modelBytes = byteData.buffer.asUint8List();
        _isInitialized = true;
        return null;
      } catch (e) {
        developer.log(
          'Failed to initialize InferenceService '
          '(attempt $attempt/$_maxInitAttempts): $e',
          name: 'InferenceService',
        );
        if (attempt < _maxInitAttempts) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }

    // Attempts exhausted for this call; a later call may retry.
    return ClassificationFailureCause.modelMissing;
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
    // `Isolate.run` exposes none, so its timeout can only stop awaiting while
    // the worker keeps holding the native interpreter and the input tensor.
    final responsePort = ReceivePort();
    Isolate? isolate;
    try {
      try {
        // Passes the model as bytes since rootBundle does not work in isolates.
        // The exit is sent to the same port, so a worker that dies before
        // answering is reported now rather than when the timeout fires.
        isolate = await Isolate.spawn(
          entryPoint,
          InferenceRequest(
            responsePort: responsePort.sendPort,
            imagePath: imagePath,
            modelBytes: _modelBytes!,
          ),
          onExit: responsePort.sendPort,
        );
      } catch (e) {
        developer.log('classify() could not spawn: $e',
            name: 'InferenceService');
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
    final report = await runInference(request.imagePath, request.modelBytes);
    request.responsePort.send(report);
  }

  /// Runs the actual inference (called inside the isolate). Each stage reports
  /// its own cause: the image, then the interpreter, then its output.
  @visibleForTesting
  static Future<ClassificationReport> runInference(
    String imagePath,
    Uint8List modelBytes,
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
      // Resizes to the size expected by the model
      final resized = img.copyResize(
        image,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      // Normalizes pixels to [0, 1] and converts to the model's format
      final input = _imageToInputTensor(resized);

      // Loads the model from bytes (works in an isolate)
      final interpreter = Interpreter.fromBuffer(modelBytes);

      // `finally` releases the native handle on every exit: the success path,
      // the early return for an incompatible model, and any throw from tensor
      // inspection or the run itself.
      try {
        // Rejects an incompatible model instead of fabricating a label.
        final inputTensor = interpreter.getInputTensor(0);
        final outputTensor = interpreter.getOutputTensor(0);
        final mismatch = checkTensors(
          inputShape: inputTensor.shape,
          inputType: inputTensor.type,
          outputShape: outputTensor.shape,
          outputType: outputTensor.type,
        );
        if (mismatch != null) return ClassificationReport.failed(mismatch);

        final numClasses = outputTensor.shape.last;
        final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);
        interpreter.run(input, output);

        return interpretOutput(output[0] as List<double>);
      } finally {
        interpreter.close();
      }
    } catch (e) {
      developer.log(
        'InferenceService.runInference failed: $e',
        name: 'InferenceService',
      );
      return const ClassificationReport.failed(
        ClassificationFailureCause.interpreterError,
      );
    }
  }

  /// The mismatch between the loaded interpreter's tensors and what this path
  /// builds and reads, or `null` when they agree: a `[1, 224, 224, 3]` float32
  /// input, and a float32 output of one probability per known label.
  @visibleForTesting
  static ClassificationFailureCause? checkTensors({
    required List<int> inputShape,
    required TensorType inputType,
    required List<int> outputShape,
    required TensorType outputType,
  }) {
    final inputAgrees =
        listEquals(inputShape, const [1, _inputSize, _inputSize, 3]) &&
            inputType == TensorType.float32;
    final outputAgrees = outputShape.length == 2 &&
        outputShape.first == 1 &&
        outputShape.last == textureLabels.length &&
        outputType == TensorType.float32;
    return inputAgrees && outputAgrees
        ? null
        : ClassificationFailureCause.modelContractMismatch;
  }

  /// The report for one output tensor: a mismatch when it does not carry one
  /// value per known label, an invalid output when a value is not a
  /// probability, and the result otherwise.
  @visibleForTesting
  static ClassificationReport interpretOutput(List<double> probabilities) {
    if (probabilities.length != textureLabels.length) {
      return const ClassificationReport.failed(
        ClassificationFailureCause.modelContractMismatch,
      );
    }
    final distribution = buildDistribution(probabilities, probabilities.length);
    if (distribution == null) {
      return const ClassificationReport.failed(
        ClassificationFailureCause.outputInvalid,
      );
    }
    // Top-1 comes from the distribution, so `distribution.first` and these two
    // fields cannot disagree.
    return ClassificationReport.ok(InferenceResult(
      textureClass: distribution.first.label,
      confidenceScore: distribution.first.probability,
      distribution: distribution,
    ));
  }

  /// Converts an image to a [1, 224, 224, 3] float32 input tensor.
  static List<List<List<List<double>>>> _imageToInputTensor(img.Image image) {
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            // image 4.x returns num for r/g/b (0-255 for 8-bit images)
            return [
              pixel.r.toDouble() / 255.0,
              pixel.g.toDouble() / 255.0,
              pixel.b.toDouble() / 255.0,
            ];
          },
        ),
      ),
    );
    return input;
  }

  /// Builds the full distribution from an output tensor, highest probability
  /// first, or null when [numClasses] does not match the label list.
  ///
  /// Probabilities are passed through verbatim. Renormalising them so they sum
  /// to 1 would hide a model that exported logits rather than probabilities,
  /// and would make every verdict threshold meaningless while looking correct.
  ///
  /// Ties break on canonical label order, ascending. Probability alone does not
  /// order the distribution — two classes can hold the same value — and the
  /// order is user-visible, because it decides which class is named as top-1
  /// and which pair an ambiguous verdict puts on screen.
  @visibleForTesting
  static List<ClassScore>? buildDistribution(
    List<double> probabilities,
    int numClasses,
  ) {
    if (numClasses != textureLabels.length) return null;
    if (probabilities.length != textureLabels.length) return null;
    // A NaN sorts above every number under `compareTo`, so it would become the
    // top-1 class and carry a NaN confidence into the result. A finite value
    // outside the unit interval is the quieter version of the same problem: it
    // sorts correctly, so nothing downstream signals anything is wrong, yet a
    // 1.1 becomes the top-1 confidence and clears every verdict threshold.
    // Rejecting the whole tensor matches how an incompatible model is handled:
    // refuse rather than fabricate a plausible-looking result.
    //
    // This is a domain check on each value, not a check that the tensor is a
    // probability distribution. Values that are individually valid can still
    // sum to anything, and they are passed through as they are — detecting
    // that belongs with calibration and the `spec.json` contract, not here.
    if (probabilities.any(
      (probability) => !ClassScore.isProbability(probability),
    )) {
      return null;
    }

    final scores = <ClassScore>[
      for (var index = 0; index < textureLabels.length; index++)
        ClassScore(
          label: textureLabels[index],
          probability: probabilities[index],
        ),
    ];
    scores.sort((first, second) {
      final byProbability = second.probability.compareTo(first.probability);
      if (byProbability != 0) return byProbability;
      return textureLabels
          .indexOf(first.label)
          .compareTo(textureLabels.indexOf(second.label));
    });
    return List.unmodifiable(scores);
  }

  /// Releases the service's resources.
  void dispose() {
    _modelBytes = null;
    _isInitialized = false;
    _permanentCause = null;
  }
}
