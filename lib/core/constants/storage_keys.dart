/// Chaves de armazenamento para Hive e outras persistências.
///
/// Centraliza strings mágicas para evitar erros de digitação.
class StorageKeys {
  StorageKeys._();

  /// Nome da box Hive para registros de solo.
  static const String soilRecordsBox = 'soil_records';
}
