import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// Provider singleton para o [InferenceService].
///
/// O serviço é criado sob demanda e descartado quando o [ProviderScope] é
/// destruído. A inicialização (carregamento do modelo) é lazy — ocorre na
/// primeira chamada a [InferenceService.classify].
final inferenceServiceProvider = Provider<InferenceService>((ref) {
  final service = InferenceService();
  ref.onDispose(service.dispose);
  return service;
});
