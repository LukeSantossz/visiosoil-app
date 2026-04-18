import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:visiosoil_app/core/database/tables/soil_records_table.dart';

part 'app_database.g.dart';

/// Banco de dados local do VisioSoil (SQLite + Drift).
///
/// Contém apenas a tabela [SoilRecords] por enquanto. Futuras tabelas devem
/// ser adicionadas ao array `tables` e acompanhadas de um aumento em
/// [schemaVersion] com a respectiva migração em [migration].
@DriftDatabase(tables: [SoilRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Construtor usado em testes para injetar um [QueryExecutor] em memória.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  // `driftDatabase` cuida do path do diretório de documentos, abertura lazy
  // e isolate adequado em cada plataforma.
  return driftDatabase(name: 'visiosoil');
}
