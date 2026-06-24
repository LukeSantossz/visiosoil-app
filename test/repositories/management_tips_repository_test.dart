// Tests for [DriftManagementTipsRepository] using an in-memory SQLite database.
//
// Mirrors `drift_soil_record_repository_test.dart`: runs on the Dart VM with
// `NativeDatabase.memory()`. The repository is a read-through cache, so the
// tests assert round-trip fidelity, single-row-per-record upserts, isolation,
// deletion, and that caching never touches the sync outbox.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_management_tips_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';

void main() {
  group('DriftManagementTipsRepository', () {
    late AppDatabase db;
    late DriftManagementTipsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftManagementTipsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    ManagementTipsResult result({
      ManagementTipsStatus status = ManagementTipsStatus.grounded,
      String tipText = 'Mantenha cobertura vegetal.',
    }) {
      return ManagementTipsResult(
        status: status,
        tips: status == ManagementTipsStatus.grounded
            ? [ManagementTip(text: tipText, citations: const [0])]
            : const [],
        sources: const [
          TipSource(
            title: 'Fonte agronômica',
            url: 'https://example.org/a',
            publisher: 'Extensão Rural',
            date: '2025-01-01',
          ),
        ],
        disclaimer: 'Orientação advisory; valide com análise local.',
        model: 'groq:llama-3.3-70b',
        retrievedAt: DateTime.utc(2026, 6, 23, 12),
      );
    }

    test('get_returns_null_when_no_cache_for_uuid', () async {
      expect(await repo.getByRecordUuid('missing'), isNull);
    });

    test('upsert_then_get_returns_equal_result', () async {
      final original = result();
      await repo.upsert('uuid-a', original);

      final fetched = await repo.getByRecordUuid('uuid-a');

      expect(fetched, isNotNull);
      expect(fetched!.toJson(), original.toJson());
    });

    test('upsert_twice_keeps_single_row_and_returns_latest', () async {
      await repo.upsert('uuid-a', result(tipText: 'Primeira versão'));
      await repo.upsert('uuid-a', result(tipText: 'Segunda versão'));

      final fetched = await repo.getByRecordUuid('uuid-a');
      expect(fetched!.tips.single.text, 'Segunda versão');

      final row = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM management_tips "
            "WHERE record_uuid = 'uuid-a'",
          )
          .getSingle();
      expect(row.read<int>('c'), 1);
    });

    test('cache_is_isolated_per_record_uuid', () async {
      await repo.upsert('uuid-a', result(tipText: 'Dica A'));
      await repo.upsert('uuid-b', result(tipText: 'Dica B'));

      expect((await repo.getByRecordUuid('uuid-a'))!.tips.single.text, 'Dica A');
      expect((await repo.getByRecordUuid('uuid-b'))!.tips.single.text, 'Dica B');
    });

    test('abstained_result_round_trips', () async {
      final abstained = result(status: ManagementTipsStatus.abstained);
      await repo.upsert('uuid-a', abstained);

      final fetched = await repo.getByRecordUuid('uuid-a');

      expect(fetched!.status, ManagementTipsStatus.abstained);
      expect(fetched.tips, isEmpty);
      expect(fetched.toJson(), abstained.toJson());
    });

    test('delete_by_uuid_removes_only_that_record_cache', () async {
      await repo.upsert('uuid-a', result());
      await repo.upsert('uuid-b', result());

      await repo.deleteByRecordUuid('uuid-a');

      expect(await repo.getByRecordUuid('uuid-a'), isNull);
      expect(await repo.getByRecordUuid('uuid-b'), isNotNull);
    });

    test('upsert_does_not_enqueue_sync_queue_row', () async {
      await repo.upsert('uuid-a', result());

      final queue = await db.customSelect('SELECT * FROM sync_queue').get();
      expect(queue, isEmpty);
    });
  });
}
