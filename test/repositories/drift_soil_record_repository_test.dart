// Testes de [DriftSoilRecordRepository] usando um banco SQLite em memória.
//
// Executa no Dart VM (sem device) — `NativeDatabase.memory()` precisa da
// biblioteca nativa do SQLite. No CI (Linux/macOS/Windows) isso funciona de
// fábrica porque `sqlite3_flutter_libs` distribui a shared library; em hosts
// sem SQLite no PATH pode ser necessário instalar o pacote `sqlite3` do SO.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/soil_record.dart';

void main() {
  group('DriftSoilRecordRepository', () {
    late AppDatabase db;
    late DriftSoilRecordRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftSoilRecordRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    SoilRecord sample({
      String imagePath = '/img.jpg',
      String? ts,
      String? textureClass,
      double? confidenceScore,
    }) {
      return SoilRecord(
        imagePath: imagePath,
        latitude: -23.5,
        longitude: -46.6,
        address: 'São Paulo',
        timestamp: ts ?? DateTime.utc(2026, 1, 1).toIso8601String(),
        textureClass: textureClass,
        confidenceScore: confidenceScore,
      );
    }

    test('create atribui id e mantém os demais campos', () async {
      final saved = await repo.create(sample());

      expect(saved.id, isNotNull);
      expect(saved.imagePath, '/img.jpg');
      expect(saved.latitude, -23.5);
      expect(saved.longitude, -46.6);
      expect(saved.address, 'São Paulo');
    });

    test('create persiste campos de classificação de textura', () async {
      final saved = await repo.create(sample(
        textureClass: 'Franco-Argiloso',
        confidenceScore: 0.92,
      ));

      expect(saved.textureClass, 'Franco-Argiloso');
      expect(saved.confidenceScore, 0.92);

      final fetched = await repo.getById(saved.id!);
      expect(fetched!.textureClass, 'Franco-Argiloso');
      expect(fetched.confidenceScore, 0.92);
    });

    test('getById roundtrip retorna o registro salvo', () async {
      final saved = await repo.create(sample());
      final fetched = await repo.getById(saved.id!);

      expect(fetched, isNotNull);
      expect(fetched!.id, saved.id);
      expect(fetched.imagePath, saved.imagePath);
    });

    test('getById retorna null quando o id não existe', () async {
      expect(await repo.getById(999), isNull);
    });

    test('getAll retorna do mais recente ao mais antigo', () async {
      final first = await repo.create(sample(imagePath: '/a.jpg'));
      final second = await repo.create(sample(imagePath: '/b.jpg'));
      final third = await repo.create(sample(imagePath: '/c.jpg'));

      final all = await repo.getAll();

      expect(all.map((r) => r.id).toList(), [third.id, second.id, first.id]);
    });

    test('getLatest retorna o registro mais recente ou null', () async {
      expect(await repo.getLatest(), isNull);

      await repo.create(sample(imagePath: '/a.jpg'));
      final second = await repo.create(sample(imagePath: '/b.jpg'));

      final latest = await repo.getLatest();
      expect(latest?.id, second.id);
    });

    test('count reflete o total de registros', () async {
      expect(await repo.count(), 0);
      await repo.create(sample());
      await repo.create(sample());
      expect(await repo.count(), 2);
    });

    test('deleteById remove apenas o registro informado', () async {
      final a = await repo.create(sample(imagePath: '/a.jpg'));
      final b = await repo.create(sample(imagePath: '/b.jpg'));

      await repo.deleteById(a.id!);

      expect(await repo.getById(a.id!), isNull);
      expect(await repo.getById(b.id!), isNotNull);
    });

    test('deleteByIds remove em lote e ignora lista vazia', () async {
      final a = await repo.create(sample(imagePath: '/a.jpg'));
      final b = await repo.create(sample(imagePath: '/b.jpg'));
      final c = await repo.create(sample(imagePath: '/c.jpg'));

      await repo.deleteByIds([]); // no-op
      expect(await repo.count(), 3);

      await repo.deleteByIds([a.id!, c.id!]);

      expect(await repo.count(), 1);
      expect(await repo.getById(b.id!), isNotNull);
    });

    test('watchAll emite a lista atualizada após inserções e deleções',
        () async {
      final stream = repo.watchAll();
      final emissions = <List<SoilRecord>>[];
      final sub = stream.listen(emissions.add);

      // Aguarda a primeira emissão (lista vazia).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final inserted = await repo.create(sample());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.deleteById(inserted.id!);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(emissions.first, isEmpty);
      expect(
        emissions.any((list) => list.length == 1 && list.first.id == inserted.id),
        isTrue,
      );
      expect(emissions.last, isEmpty);
    });
  });
}
