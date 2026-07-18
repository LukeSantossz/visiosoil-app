import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result of soil texture classification inference.
class InferenceResult {
  final String textureClass;
  final double confidenceScore;

  const InferenceResult({
    required this.textureClass,
    required this.confidenceScore,
  });
}

/// Parameters for running inference in an isolate.
class _InferenceParams {
  final String imagePath;
  final Uint8List modelBytes;

  const _InferenceParams({
    required this.imagePath,
    required this.modelBytes,
  });
}

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

  /// Soil texture classes aligned with ml/config.yaml.
  /// The order must match the trained model's outputs.
  static const List<String> _textureLabels = [
    'Arenosa',
    'Media',
    'Siltosa',
    'Muito Argilosa',
    'Argilosa',
  ];

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

  /// Set when the model asset is empty or absent — a build-time fact that
  /// retrying cannot fix, so further initialization attempts are skipped.
  bool _modelUnavailable = false;

  /// Indicates whether the service is ready for inference.
  bool get isReady => _isInitialized && _modelBytes != null;

  /// Initializes the service by loading the model from assets.
  ///
  /// Returns `true` once the model bytes are loaded, `false` otherwise. The
  /// model is loaded as bytes so it can be passed to the isolate. Transient
  /// failures are retried with a short backoff; an empty or absent model is a
  /// build-time fact and is not retried (see [_modelUnavailable]).
  ///
  /// [assetLoader] and [retryDelay] are injectable for tests.
  Future<bool> initialize({
    ModelAssetLoader? assetLoader,
    Duration retryDelay = _initRetryDelay,
  }) async {
    if (_isInitialized) return true;
    if (_modelUnavailable) return false;

    final load = assetLoader ?? rootBundle.load;

    for (var attempt = 1; attempt <= _maxInitAttempts; attempt++) {
      try {
        final byteData = await load(_modelPath).timeout(
          _modelLoadTimeout,
          onTimeout: () => throw Exception('Timeout loading model'),
        );
        if (byteData.lengthInBytes == 0) {
          // An empty model will not change without a new build: do not retry.
          _modelUnavailable = true;
          return false;
        }
        _modelBytes = byteData.buffer.asUint8List();
        _isInitialized = true;
        return true;
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

    // Transient failures exhausted for this call; a later call may retry.
    return false;
  }

  /// Runs soil texture classification on an image.
  ///
  /// [imagePath] is the absolute path of the image to classify.
  /// Returns `null` if the service is not initialized or if an error occurs.
  Future<InferenceResult?> classify(String imagePath) async {
    if (!isReady) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    try {
      // Runs inference in an isolate to avoid blocking the UI
      // Passes the model as bytes since rootBundle does not work in isolates
      final params = _InferenceParams(
        imagePath: imagePath,
        modelBytes: _modelBytes!,
      );
      final result = await Isolate.run(() => _runInference(params))
          .timeout(_inferenceTimeout);
      return result;
    } catch (e) {
      developer.log(
        'classify() failed: $e',
        name: 'InferenceService',
      );
      return null;
    }
  }

  /// Runs the actual inference (called inside the isolate).
  static Future<InferenceResult?> _runInference(_InferenceParams params) async {
    try {
      // Loads and preprocesses the image
      final imageFile = File(params.imagePath);
      if (!imageFile.existsSync()) return null;

      final imageBytes = imageFile.readAsBytesSync();
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

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
      final interpreter = Interpreter.fromBuffer(params.modelBytes);

      // `finally` releases the native handle on every exit: the success path,
      // the early return for an incompatible model, and any throw from tensor
      // inspection or the run itself.
      try {
        // Output shape: [1, numClasses]
        final outputShape = interpreter.getOutputTensor(0).shape;
        final numClasses = outputShape.last;
        final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

        // Runs inference
        interpreter.run(input, output);

        // Finds the class with the highest probability
        final probabilities = (output[0] as List<double>);
        int maxIndex = 0;
        double maxProb = probabilities[0];
        for (int i = 1; i < probabilities.length; i++) {
          if (probabilities[i] > maxProb) {
            maxProb = probabilities[i];
            maxIndex = i;
          }
        }

        // Rejects incompatible models instead of fabricating a label.
        final label = resolveTextureLabel(maxIndex, numClasses);
        if (label == null) return null;

        return InferenceResult(
          textureClass: label,
          confidenceScore: maxProb,
        );
      } finally {
        interpreter.close();
      }
    } catch (e) {
      developer.log(
        'InferenceService._runInference failed: $e',
        name: 'InferenceService',
      );
      return null;
    }
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

  /// Maps the predicted [index] to a soil texture label, rejecting models whose
  /// output [numClasses] does not match the known labels (returns null) so an
  /// incompatible model never yields a fabricated, plausible-looking result.
  @visibleForTesting
  static String? resolveTextureLabel(int index, int numClasses) {
    if (numClasses != _textureLabels.length) return null;
    if (index < 0 || index >= _textureLabels.length) return null;
    return _textureLabels[index];
  }

  /// Releases the service's resources.
  void dispose() {
    _modelBytes = null;
    _isInitialized = false;
    _modelUnavailable = false;
  }
}
