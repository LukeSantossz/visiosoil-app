import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:visiosoil_app/core/data/repositories/management_tips_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';

/// Drift/SQLite implementation of [ManagementTipsRepository].
///
/// Stores one row per Soil Record, keyed by `record_uuid`, with the whole
/// [ManagementTipsResult] serialized into `payload_json`. Writes upsert by uuid
/// (refetch replaces the prior entry); reads decode the payload back to the
/// domain model. No Drift type escapes through this boundary.
class DriftManagementTipsRepository implements ManagementTipsRepository {
  DriftManagementTipsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<ManagementTipsResult?> getByRecordUuid(String recordUuid) async =>
      (await getCached(recordUuid))?.result;

  @override
  Future<CachedManagementTips?> getCached(String recordUuid) async {
    final row = await (_db.select(_db.managementTips)
          ..where((t) => t.recordUuid.equals(recordUuid)))
        .getSingleOrNull();
    if (row == null) return null;
    final json = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    return CachedManagementTips(
      result: ManagementTipsResult.fromJson(json),
      corpusVersion: row.corpusVersion,
    );
  }

  @override
  Future<void> upsert(String recordUuid, ManagementTipsResult result) async {
    await _db.into(_db.managementTips).insertOnConflictUpdate(
          ManagementTipsCompanion.insert(
            recordUuid: recordUuid,
            payloadJson: jsonEncode(result.toJson()),
            retrievedAt: result.retrievedAt.toUtc().toIso8601String(),
            // Duplicated out of the payload so staleness is a column read rather
            // than a decode of every row.
            corpusVersion: Value(result.corpusVersion),
          ),
        );
  }

  @override
  Future<void> deleteByRecordUuid(String recordUuid) async {
    await (_db.delete(_db.managementTips)
          ..where((t) => t.recordUuid.equals(recordUuid)))
        .go();
  }
}
