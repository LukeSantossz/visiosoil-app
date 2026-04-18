import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/database/app_database.dart';

/// Fornece uma instância singleton de [AppDatabase] enquanto o [ProviderScope]
/// estiver vivo. O banco é fechado automaticamente no descarte do provider.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
