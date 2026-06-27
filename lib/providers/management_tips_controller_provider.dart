import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/research/management_tips_controller.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';

/// Wires [ManagementTipsController] with the live service, cache, and
/// connectivity providers. The Details tips section calls `generate(record)`
/// on it.
final managementTipsControllerProvider = Provider<ManagementTipsController>((ref) {
  return ManagementTipsController(
    researchService: ref.watch(researchServiceProvider),
    repository: ref.watch(managementTipsRepositoryProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
