import 'package:visiosoil_app/core/utils/formatters.dart';

/// Soil sample record (domain model).
///
/// The [id] is null before persistence and filled in by the repository after
/// the insertion into the database.
class SoilRecord {
  final int? id;
  final String imagePath;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String timestamp;
  final String? textureClass;
  final double? confidenceScore;

  const SoilRecord({
    this.id,
    required this.imagePath,
    this.latitude,
    this.longitude,
    this.address,
    required this.timestamp,
    this.textureClass,
    this.confidenceScore,
  });

  /// Returns a copy of this record with the given fields replaced.
  SoilRecord copyWith({
    int? id,
    String? imagePath,
    double? latitude,
    double? longitude,
    String? address,
    String? timestamp,
    String? textureClass,
    double? confidenceScore,
  }) {
    return SoilRecord(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
      textureClass: textureClass ?? this.textureClass,
      confidenceScore: confidenceScore ?? this.confidenceScore,
    );
  }

  /// Indicates whether the record has valid GPS coordinates.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Indicates whether the record has a valid address.
  bool get hasValidAddress =>
      address != null &&
      address!.isNotEmpty &&
      address != 'Localização não disponível' &&
      address != 'Localização não informada';

  /// Returns the timestamp formatted for display.
  String get formattedTimestamp => Formatters.timestamp(timestamp);

  /// Returns the timestamp formatted in compact form.
  String get formattedTimestampCompact =>
      Formatters.timestampCompact(timestamp);

  /// Returns the formatted coordinates.
  String get formattedCoordinates => hasCoordinates
      ? Formatters.coordinates(latitude!, longitude!)
      : 'Coordenadas não disponíveis';

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
