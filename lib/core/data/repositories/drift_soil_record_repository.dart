import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/data/sync/sync_operation.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/core/database/soil_record_mapper.dart';
import 'package:visiosoil_app/core/services/image_storage_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Drift/SQLite-based implementation of [SoilRecordRepository].
///
/// Concentrates all conversion between Drift rows ([SoilRecordRow]) and the
/// domain model [SoilRecord]. No Drift-specific type escapes through this
/// boundary.
///
/// Every mutation maintains sync metadata: [create] assigns a client-generated
/// UUID v4 and enqueues an `upsert`; the delete paths write a tombstone
/// ([SoilRecords.deleted]) and enqueue a `delete` instead of removing the row,
/// so deletions propagate on sync. All reads exclude tombstoned rows.
class DriftSoilRecordRepository implements SoilRecordRepository {
  DriftSoilRecordRepository(
    this._db, {
    String Function()? uuidFactory,
    DateTime Function()? clock,
    ImageStorageService? imageStorage,
  })  : _uuidFactory = uuidFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now,
        _imageStorage = imageStorage ?? DefaultImageStorageService();

  /// Escape character for the `LIKE` clause in [watchFiltered], so a `%` or
  /// `_` typed by the user matches itself instead of acting as a wildcard.
  static const String _likeEscapeChar = r'\';

  final AppDatabase _db;
  final String Function() _uuidFactory;
  final DateTime Function() _clock;
  final ImageStorageService _imageStorage;

  String _now() => _clock().toUtc().toIso8601String();

  @override
  Future<SoilRecord> create(SoilRecord record) async {
    final uuid = _uuidFactory();
    final now = _now();

    // Copy the captured photo into durable storage BEFORE any DB work, so a
    // copy failure aborts the create with no row inserted (no orphan record).
    final stableImagePath = await _imageStorage.saveCapturedImage(
      File(record.imagePath),
      recordUuid: uuid,
    );

    final int id;
    try {
      id = await _db.transaction(() async {
        final insertedId = await _db.into(_db.soilRecords).insert(
              SoilRecordsCompanion.insert(
                uuid: uuid,
                imagePath: stableImagePath,
                latitude: Value(record.latitude),
                longitude: Value(record.longitude),
                address: Value(record.address),
                timestamp: record.timestamp,
                updatedAt: now,
                textureClass: Value(record.textureClass),
                confidenceScore: Value(record.confidenceScore),
              ),
            );
        await _enqueue(uuid, SyncOperation.upsert, now);
        return insertedId;
      });
    } catch (_) {
      // The copy already succeeded; if the DB write fails the stored file would
      // be orphaned (no row references it). Best-effort cleanup, then rethrow
      // the original error so the caller still sees the failure.
      try {
        await File(stableImagePath).delete();
      } on FileSystemException {
        // File may already be absent; nothing more to do.
      }
      rethrow;
    }

    return record.copyWith(
      id: id,
      uuid: uuid,
      imagePath: stableImagePath,
      updatedAt: now,
      syncStatus: 'pending',
      deleted: false,
    );
  }

  @override
  Future<SoilRecord?> getById(int id) async {
    final row = await (_db.select(_db.soilRecords)
          ..where((t) => t.id.equals(id) & t.deleted.equals(false)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Stream<List<SoilRecord>> watchAll() {
    final query = _db.select(_db.soilRecords)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<List<SoilRecord>> getAll() async {
    final query = _db.select(_db.soilRecords)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ]);
    final rows = await query.get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<SoilRecord?> getLatest() async {
    final query = _db.select(_db.soilRecords)
      ..where((t) => t.deleted.equals(false))
      ..orderBy([
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<int> count() async {
    final countExp = _db.soilRecords.id.count();
    final query = _db.selectOnly(_db.soilRecords)
      ..addColumns([countExp])
      ..where(_db.soilRecords.deleted.equals(false));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  @override
  Future<void> deleteById(int id) async {
    await _tombstone((t) => t.id.equals(id));
  }

  @override
  Future<void> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await _tombstone((t) => t.id.isIn(ids));
  }

  @override
  Future<void> deleteAll() async {
    // `_tombstone` already restricts to non-deleted rows.
    await _tombstone((t) => const Constant(true));
  }

  @override
  Stream<List<SoilRecord>> watchFiltered({
    String? textureClass,
    String? searchTerm,
  }) {
    var query = _db.select(_db.soilRecords);

    // Applies filters conditionally
    query = query..where((t) {
      Expression<bool> condition = t.deleted.equals(false);

      // Filter by texture class (exact match)
      if (textureClass != null && textureClass.isNotEmpty) {
        condition = condition & t.textureClass.equals(textureClass);
      }

      // Filter by search term on the address (case-insensitive LIKE).
      // The term is a literal substring, not a pattern: it is trimmed, and the
      // LIKE metacharacters (% and _) plus the escape character itself are
      // escaped so they match themselves. A term that is empty after trimming
      // carries no content and joins the no-filter path.
      final trimmed = searchTerm?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        final escaped = trimmed
            .toLowerCase()
            .replaceAll(_likeEscapeChar, '$_likeEscapeChar$_likeEscapeChar')
            .replaceAll('%', '$_likeEscapeChar%')
            .replaceAll('_', '${_likeEscapeChar}_');
        condition = condition &
            t.address.lower().like(
                  '%$escaped%',
                  escapeChar: _likeEscapeChar,
                );
      }

      return condition;
    });

    // Orders from most recent to oldest
    query = query..orderBy([
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);

    return query.watch().map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<List<String>> getDistinctTextureClasses() async {
    final query = _db.selectOnly(_db.soilRecords, distinct: true)
      ..addColumns([_db.soilRecords.textureClass])
      ..where(_db.soilRecords.textureClass.isNotNull() &
          _db.soilRecords.deleted.equals(false));

    final rows = await query.get();
    return rows
        .map((row) => row.read(_db.soilRecords.textureClass))
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toList();
  }

  /// Marks the rows matching [filter] as deleted (tombstone) and enqueues a
  /// `delete` operation per affected record, in a single transaction; already
  /// tombstoned rows are left untouched. After the transaction commits, each
  /// affected record's image file is deleted best-effort.
  Future<void> _tombstone(
    Expression<bool> Function($SoilRecordsTable t) filter,
  ) async {
    final now = _now();
    final imagePaths = await _db.transaction(() async {
      final rows = await (_db.select(_db.soilRecords)
            ..where((t) => filter(t) & t.deleted.equals(false)))
          .get();
      if (rows.isEmpty) return <String>[];

      for (final row in rows) {
        await (_db.update(_db.soilRecords)
              ..where((t) => t.id.equals(row.id)))
            .write(
          SoilRecordsCompanion(
            deleted: const Value(true),
            syncStatus: const Value('pending'),
            updatedAt: Value(now),
          ),
        );
        await _enqueue(row.uuid, SyncOperation.delete, now);
      }
      return rows.map((row) => row.imagePath).toList();
    });

    // After the tombstone has committed, delete each record's image file
    // best-effort: the row removal is the user's primary intent, so a failure
    // to delete a file is logged and tolerated, never allowed to abort the
    // already-committed tombstone or block the remaining files.
    for (final imagePath in imagePaths) {
      try {
        await _imageStorage.deleteImage(imagePath);
      } on FileSystemException catch (error) {
        developer.log(
          'failed to delete image file: $imagePath',
          name: 'DriftSoilRecordRepository',
          error: error,
        );
      }
    }
  }

  /// Appends an operation to the `sync_queue` outbox.
  Future<void> _enqueue(
    String recordUuid,
    SyncOperation operation,
    String createdAt,
  ) async {
    await _db.into(_db.syncQueue).insert(
          SyncQueueCompanion.insert(
            recordUuid: recordUuid,
            operation: operation.name,
            createdAt: createdAt,
          ),
        );
  }

  SoilRecord _toDomain(SoilRecordRow row) => soilRecordFromRow(row);
}
