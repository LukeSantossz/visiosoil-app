import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/models/class_score.dart';

/// Soil sample record (domain model).
///
/// The [id] is null before persistence and filled in by the repository after
/// the insertion into the database. Sync fields ([uuid], [updatedAt],
/// [syncStatus], [deleted], [remoteId]) are likewise assigned by the
/// repository: callers construct records without them.
class SoilRecord {
  final int? id;
  final String? uuid;
  final String? remoteId;
  final String imagePath;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String timestamp;
  final String? updatedAt;
  final String syncStatus;
  final bool deleted;
  final String? textureClass;
  final double? confidenceScore;

  /// Every class's probability, in the contract's class order, as the
  /// classification scored them (SPEC 0097). Null when not known: a record
  /// saved before schema v7, or without a classification.
  final List<ClassScore>? classDistribution;

  /// The versions of the contract that scored the photograph, null when not
  /// known.
  final String? modelVersion;
  final String? datasetVersion;

  /// The radius in metres the device reported for the GPS fix (SPEC 0148).
  /// Null when not known: a record saved before schema v8, without a
  /// location, or whose device reported no usable accuracy.
  final double? horizontalAccuracy;

  const SoilRecord({
    this.id,
    this.uuid,
    this.remoteId,
    required this.imagePath,
    this.latitude,
    this.longitude,
    this.address,
    required this.timestamp,
    this.updatedAt,
    this.syncStatus = 'pending',
    this.deleted = false,
    this.textureClass,
    this.confidenceScore,
    this.classDistribution,
    this.modelVersion,
    this.datasetVersion,
    this.horizontalAccuracy,
  });

  /// Returns a copy of this record with the given fields replaced.
  SoilRecord copyWith({
    int? id,
    String? uuid,
    String? remoteId,
    String? imagePath,
    double? latitude,
    double? longitude,
    String? address,
    String? timestamp,
    String? updatedAt,
    String? syncStatus,
    bool? deleted,
    String? textureClass,
    double? confidenceScore,
    List<ClassScore>? classDistribution,
    String? modelVersion,
    String? datasetVersion,
    double? horizontalAccuracy,
  }) {
    return SoilRecord(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      remoteId: remoteId ?? this.remoteId,
      imagePath: imagePath ?? this.imagePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      deleted: deleted ?? this.deleted,
      textureClass: textureClass ?? this.textureClass,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      classDistribution: classDistribution ?? this.classDistribution,
      modelVersion: modelVersion ?? this.modelVersion,
      datasetVersion: datasetVersion ?? this.datasetVersion,
      horizontalAccuracy: horizontalAccuracy ?? this.horizontalAccuracy,
    );
  }

  /// Indicates whether the record has valid GPS coordinates.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Indicates whether the record has a valid address.
  bool get hasValidAddress =>
      address != null &&
      address!.isNotEmpty &&
      address != AppStrings.addressUnavailable;

  /// Returns the timestamp formatted for display.
  String get formattedTimestamp => Formatters.timestamp(timestamp);

  /// Returns the timestamp formatted in compact form.
  String get formattedTimestampCompact =>
      Formatters.timestampCompact(timestamp);

  /// Returns the formatted coordinates.
  String get formattedCoordinates => hasCoordinates
      ? Formatters.coordinates(latitude!, longitude!)
      : 'Coordenadas não disponíveis';

  /// Returns the GPS fix's accuracy as the device estimated it, or a message
  /// saying it is not known, so an unknown accuracy is never shown as a
  /// value (SPEC 0148).
  String get formattedHorizontalAccuracy => horizontalAccuracy != null
      ? 'Precisão estimada: ${Formatters.horizontalAccuracy(horizontalAccuracy!)}'
      : 'Precisão não disponível';

  /// Returns the address or a default message.
  String get displayAddress =>
      hasValidAddress ? address! : 'Endereço não disponível';

  /// Indicates whether the record has a texture classification.
  bool get hasClassification => textureClass != null && textureClass!.isNotEmpty;

  /// Returns the texture class or a default message.
  String get displayTextureClass =>
      hasClassification ? textureClass! : 'Não classificado';

  /// Returns the confidence score formatted as a percentage.
  String get formattedConfidence => confidenceScore != null
      ? '${(confidenceScore! * 100).toStringAsFixed(1)}%'
      : '-';
}
