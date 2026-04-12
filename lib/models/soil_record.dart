import 'package:hive/hive.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';

part 'soil_record.g.dart';

@HiveType(typeId: 0)
class SoilRecord {
  @HiveField(0)
  final String imagePath;

  @HiveField(1)
  final double? latitude;

  @HiveField(2)
  final double? longitude;

  @HiveField(3)
  final String? address;

  @HiveField(4)
  final String timestamp;

  SoilRecord({
    required this.imagePath,
    this.latitude,
    this.longitude,
    this.address,
    required this.timestamp,
  });

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
