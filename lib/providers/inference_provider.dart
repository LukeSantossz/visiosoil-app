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

/// The released contract's classes, in its order: the collection's list and
/// its total (SPEC 0223). Read through [InferenceService] so the contract is
/// parsed in one place; fails when the contract cannot be read.
final contractClassesProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(inferenceServiceProvider);
  final cause = await service.initialize();
  if (cause != null) {
    throw StateError('The contract is unavailable: ${cause.name}');
  }
  return service.contract!.classes;
});
