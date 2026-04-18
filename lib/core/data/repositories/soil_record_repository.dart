import 'package:visiosoil_app/models/soil_record.dart';

/// Contrato de persistência para [SoilRecord].
///
/// A UI depende apenas desta interface: tipos específicos do Drift nunca
/// vazam para as camadas de apresentação. Uma implementação baseada em outro
/// mecanismo (ex.: API remota) poderia ser plugada sem alterar as telas.
abstract class SoilRecordRepository {
  /// Persiste [record] e retorna uma cópia com o [SoilRecord.id] preenchido.
  Future<SoilRecord> create(SoilRecord record);

  /// Retorna o registro com o [id] informado ou `null` se não existir.
  Future<SoilRecord?> getById(int id);

  /// Emite a lista completa de registros, ordenada do mais recente ao mais
  /// antigo, reagindo a mudanças no banco.
  Stream<List<SoilRecord>> watchAll();

  /// Lê a lista completa de registros, ordenada do mais recente ao mais
  /// antigo, em uma única requisição.
  Future<List<SoilRecord>> getAll();

  /// Retorna o registro mais recente ou `null` se o banco estiver vazio.
  Future<SoilRecord?> getLatest();

  /// Retorna a quantidade total de registros.
  Future<int> count();

  /// Remove o registro com o [id] informado. No-op se não existir.
  Future<void> deleteById(int id);

  /// Remove em lote os registros cujos ids constam em [ids].
  Future<void> deleteByIds(List<int> ids);
}
