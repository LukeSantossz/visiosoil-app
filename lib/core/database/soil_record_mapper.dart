import 'dart:convert';
import 'dart:developer' as developer;

import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/class_score.dart';
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
      classDistribution: decodeClassDistribution(row.classDistribution),
      modelVersion: row.modelVersion,
      datasetVersion: row.datasetVersion,
    );

/// The `class_distribution` column's text for [distribution]: a JSON array of
/// `{"label", "probability"}` in the order given, which is the contract's
/// (SPEC 0097). Null stays null.
String? encodeClassDistribution(List<ClassScore>? distribution) =>
    distribution == null
        ? null
        : jsonEncode([
            for (final score in distribution)
              {'label': score.label, 'probability': score.probability},
          ]);

/// The distribution [text] holds, or null when it holds none.
///
/// Only the app writes the column, so text that does not decode to that shape
/// means corruption. It reads as none, and is logged, because one bad row must
/// not stop history from rendering the top-1 the record still has.
List<ClassScore>? decodeClassDistribution(String? text) {
  if (text == null) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! List) throw const FormatException('not a JSON array');
    return [
      for (final entry in decoded)
        if (entry is Map &&
            entry['label'] is String &&
            entry['probability'] is num)
          ClassScore(
            label: entry['label'] as String,
            probability: (entry['probability'] as num).toDouble(),
          )
        else
          throw FormatException('not a label and a probability: $entry'),
    ];
  } on FormatException catch (error) {
    developer.log(
      'unreadable class_distribution: ${error.message}',
      name: 'SoilRecordMapper',
    );
    return null;
  }
}
