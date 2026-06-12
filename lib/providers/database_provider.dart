import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

/// Provides a singleton [AppDatabase] instance while the [ProviderScope]
/// is alive. The database is closed automatically when the provider is disposed.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
