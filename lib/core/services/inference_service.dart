import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Resultado da inferência de classificação de textura do solo.
class InferenceResult {
  final String textureClass;
  final double confidenceScore;

  const InferenceResult({
    required this.textureClass,
    required this.confidenceScore,
  });
}

/// Parâmetros para execução de inferência em isolate.
class _InferenceParams {
  final String imagePath;
  final Uint8List modelBytes;

  const _InferenceParams({
    required this.imagePath,
    required this.modelBytes,
  });
}

/// Serviço de inferência TensorFlow Lite para classificação de textura do solo.
///
/// Carrega o modelo dos assets, pré-processa imagens e executa inferência
/// on-device. A inferência é executada em isolate para não bloquear a thread
/// principal.
class InferenceService {
  static const String _modelPath = 'assets/models/soil_classifier.tflite';

  /// Dimensão de entrada do modelo (224x224 RGB).
  static const int _inputSize = 224;

  /// Classes de textura do solo (USDA Soil Texture Triangle).
  /// A ordem deve corresponder às saídas do modelo treinado.
  static const List<String> _textureLabels = [
    'Areia',
    'Areia Franca',
    'Franco-Arenoso',
    'Franco',
    'Franco-Siltoso',
    'Silte',
    'Franco-Argilo-Arenoso',
    'Franco-Argiloso',
    'Franco-Argilo-Siltoso',
    'Argila-Arenosa',
    'Argila-Siltosa',
    'Argila',
  ];

  Uint8List? _modelBytes;
  bool _isInitialized = false;
  bool _initializationAttempted = false;

  /// Indica se o serviço está pronto para inferência.
  bool get isReady => _isInitialized && _modelBytes != null;

  /// Inicializa o serviço carregando o modelo dos assets.
  ///
  /// Retorna `true` se inicializado com sucesso, `false` caso contrário.
  /// O modelo é carregado como bytes para poder ser passado ao isolate.
  /// Se a inicialização já foi tentada e falhou, retorna `false` imediatamente.
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    // Evita tentativas repetidas de carregar modelo inexistente
    if (_initializationAttempted) return false;
    _initializationAttempted = true;

    try {
      // Timeout para evitar travamento se o arquivo não existir
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
      // Modelo não encontrado, timeout ou erro de carregamento
      _isInitialized = false;
      return false;
    }
  }

  /// Executa classificação de textura do solo em uma imagem.
  ///
  /// [imagePath] é o caminho absoluto da imagem a ser classificada.
  /// Retorna `null` se o serviço não estiver inicializado ou se ocorrer erro.
  Future<InferenceResult?> classify(String imagePath) async {
    if (!isReady) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    try {
      // Executa inferência em isolate para não bloquear a UI
      // Passa o modelo como bytes pois rootBundle não funciona em isolates
      final params = _InferenceParams(
        imagePath: imagePath,
        modelBytes: _modelBytes!,
      );
      final result = await Isolate.run(() => _runInference(params));
      return result;
    } catch (e) {
      return null;
    }
  }

  /// Executa a inferência propriamente dita (chamada dentro do isolate).
  static Future<InferenceResult?> _runInference(_InferenceParams params) async {
    try {
      // Carrega e pré-processa a imagem
      final imageFile = File(params.imagePath);
      if (!imageFile.existsSync()) return null;

      final imageBytes = imageFile.readAsBytesSync();
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      // Resize para o tamanho esperado pelo modelo
      final resized = img.copyResize(
        image,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      // Normaliza pixels para [0, 1] e converte para formato do modelo
      final input = _imageToInputTensor(resized);

      // Carrega o modelo a partir dos bytes (funciona em isolate)
      final interpreter = Interpreter.fromBuffer(params.modelBytes);

      // Output shape: [1, numClasses]
      final outputShape = interpreter.getOutputTensor(0).shape;
      final numClasses = outputShape.last;
      final output = List.filled(numClasses, 0.0).reshape([1, numClasses]);

      // Executa inferência
      interpreter.run(input, output);
      interpreter.close();

      // Encontra classe com maior probabilidade
      final probabilities = (output[0] as List<double>);
      int maxIndex = 0;
      double maxProb = probabilities[0];
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      // Mapeia índice para label
      final label = maxIndex < _textureLabels.length
          ? _textureLabels[maxIndex]
          : 'Classe $maxIndex';

      return InferenceResult(
        textureClass: label,
        confidenceScore: maxProb,
      );
    } catch (e) {
      return null;
    }
  }

  /// Converte imagem para tensor de entrada [1, 224, 224, 3] float32.
  static List<List<List<List<double>>>> _imageToInputTensor(img.Image image) {
    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            // image 4.x retorna num para r/g/b (0-255 para imagens 8-bit)
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

  /// Libera recursos do serviço.
  void dispose() {
    _modelBytes = null;
    _isInitialized = false;
    _initializationAttempted = false;
  }
}
