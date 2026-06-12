import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// Singleton provider for the [InferenceService].
///
/// The service is created on demand and discarded when the [ProviderScope] is
/// destroyed. Initialization (model loading) is lazy — it happens on the
/// first call to [InferenceService.classify].
final inferenceServiceProvider = Provider<InferenceService>((ref) {
  final service = InferenceService();
  ref.onDispose(service.dispose);
  return service;
});
