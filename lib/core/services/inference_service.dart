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

  Uint8List? _modelBytes;
  bool _isInitialized = false;
  bool _initializationAttempted = false;

  /// Indicates whether the service is ready for inference.
  bool get isReady => _isInitialized && _modelBytes != null;

  /// Initializes the service by loading the model from assets.
  ///
  /// Returns `true` if initialized successfully, `false` otherwise.
  /// The model is loaded as bytes so it can be passed to the isolate.
  /// If initialization was already attempted and failed, returns `false` immediately.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // Avoids repeated attempts to load a nonexistent model
    if (_initializationAttempted) return false;
    _initializationAttempted = true;

    try {
      // Timeout to avoid hanging if the file does not exist
      final byteData = await rootBundle.load(_modelPath).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout loading model'),
      );
      if (byteData.lengthInBytes == 0) {
        return false;
      }
      _modelBytes = byteData.buffer.asUint8List();
      _isInitialized = true;
      return true;
    } catch (e) {
      developer.log(
        'Failed to initialize InferenceService: $e',
        name: 'InferenceService',
      );
      _isInitialized = false;
      return false;
    }
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
      final result = await Isolate.run(() => _runInference(params));
      return result;
    } catch (e) {
      developer.log(
        'classify() failed for $imagePath: $e',
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

      // Output shape: [1, numClasses]
      final outputShape = interpreter.getOutputTensor(0).shape;
      final numClasses = outputShape.last;
      final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

      // Runs inference
      interpreter.run(input, output);
      interpreter.close();

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

      // Maps index to label
      final label = maxIndex < _textureLabels.length
          ? _textureLabels[maxIndex]
          : 'Classe $maxIndex';

      return InferenceResult(
        textureClass: label,
        confidenceScore: maxProb,
      );
    } catch (e) {
      debugPrint('InferenceService._runInference failed: $e');
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

  /// Releases the service's resources.
  void dispose() {
    _modelBytes = null;
    _isInitialized = false;
    _initializationAttempted = false;
  }
}
