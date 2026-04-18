import 'package:visiosoil_app/core/utils/formatters.dart';

/// Registro de amostra de solo (modelo de domínio).
///
/// O [id] é nulo antes da persistência e preenchido pelo repositório após
/// a inserção no banco de dados.
class SoilRecord {
  final int? id;
  final String imagePath;
  final double? latitude;
  final double? longitude;
  final String? address;
  final String timestamp;

  const SoilRecord({
    this.id,
    required this.imagePath,
    this.latitude,
    this.longitude,
    this.address,
    required this.timestamp,
  });

  /// Retorna uma cópia deste registro com os campos informados substituídos.
  SoilRecord copyWith({
    int? id,
    String? imagePath,
    double? latitude,
    double? longitude,
    String? address,
    String? timestamp,
  }) {
    return SoilRecord(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Indica se o registro possui coordenadas GPS válidas.
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Indica se o registro possui um endereço válido.
  bool get hasValidAddress =>
      address != null &&
      address!.isNotEmpty &&
      address != 'Localização não disponível' &&
      address != 'Localização não informada' &&
      address != 'Localização indisponível para imagens da galeria';

  /// Retorna o timestamp formatado para exibição.
  String get formattedTimestamp => Formatters.timestamp(timestamp);

  /// Retorna o timestamp formatado de forma compacta.
  String get formattedTimestampCompact =>
      Formatters.timestampCompact(timestamp);

  /// Retorna as coordenadas formatadas.
  String get formattedCoordinates => hasCoordinates
      ? Formatters.coordinates(latitude!, longitude!)
      : 'Coordenadas não disponíveis';

  /// Retorna o endereço ou uma mensagem padrão.
  String get displayAddress =>
      hasValidAddress ? address! : 'Endereço não disponível';
}
