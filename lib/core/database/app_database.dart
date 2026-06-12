import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:visiosoil_app/core/database/tables/soil_records_table.dart';

part 'app_database.g.dart';

/// VisioSoil local database (SQLite + Drift).
///
/// Contains only the [SoilRecords] table for now. Future tables must
/// be added to the `tables` array and accompanied by a bump in
/// [schemaVersion] with the corresponding migration in [migration].
@DriftDatabase(tables: [SoilRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor used in tests to inject an in-memory [QueryExecutor].
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // v1 → v2: adds texture classification columns
            await migrator.addColumn(soilRecords, soilRecords.textureClass);
            await migrator.addColumn(soilRecords, soilRecords.confidenceScore);
          }
        },
      );
}

QueryExecutor _openConnection() {
  // `driftDatabase` takes care of the documents directory path, lazy opening,
  // and the appropriate isolate on each platform.
  return driftDatabase(name: 'visiosoil');
}
