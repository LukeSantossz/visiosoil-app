import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Maps a Drift [SoilRecordRow] to the domain [SoilRecord].
///
/// Shared by the repository and the sync store so the row-to-domain conversion
/// lives in one place.
SoilRecord soilRecordFromRow(SoilRecordRow row) => SoilRecord(
      id: row.id,
      uuid: row.uuid,
      remoteId: row.remoteId,
      imagePath: row.imagePath,
      latitude: row.latitude,
      longitude: row.longitude,
      address: row.address,
      timestamp: row.timestamp,
      updatedAt: row.updatedAt,
      syncStatus: row.syncStatus,
      deleted: row.deleted,
      textureClass: row.textureClass,
      confidenceScore: row.confidenceScore,
    );
