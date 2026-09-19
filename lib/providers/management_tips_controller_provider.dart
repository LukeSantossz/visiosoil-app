import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/research/management_tips_controller.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/site_resolver_provider.dart';

/// Wires [ManagementTipsController] with the live service, cache and site
/// resolver. The Details tips section calls `generate(record)` on it.
///
/// No connectivity provider: Tier 1 composes on the device, so being offline is
/// not a reason to refuse. That gate belongs to corpus fetch, in slice A4.
final managementTipsControllerProvider = Provider<ManagementTipsController>((ref) {
  return ManagementTipsController(
    researchService: ref.watch(researchServiceProvider),
    repository: ref.watch(managementTipsRepositoryProvider),
    siteResolver: ref.watch(siteResolverProvider),
  );
});
