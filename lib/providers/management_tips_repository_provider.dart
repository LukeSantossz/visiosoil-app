import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/data/repositories/drift_management_tips_repository.dart';
import 'package:visiosoil_app/core/data/repositories/management_tips_repository.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/providers/database_provider.dart';

/// Exposes the cache **through the interface** [ManagementTipsRepository].
/// Screens and the research layer must never read the Drift implementation
/// directly.
final managementTipsRepositoryProvider =
    Provider<ManagementTipsRepository>((ref) {
  return DriftManagementTipsRepository(ref.watch(appDatabaseProvider));
});

/// Reads cached tips for a record by its global `uuid`, or `null` if none are
/// stored. The online fetch-or-cache flow (keyed by record id) is layered on
/// top of this in the details feature.
final cachedManagementTipsProvider =
    FutureProvider.family<ManagementTipsResult?, String>((ref, recordUuid) {
  return ref.watch(managementTipsRepositoryProvider).getByRecordUuid(recordUuid);
});
