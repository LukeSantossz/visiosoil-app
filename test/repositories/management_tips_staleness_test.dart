// The cache records which corpus answered, and reports staleness rather than
// deciding it.
//
// Staleness is **exact string inequality, not ordering**. A corpus version is a
// release label, not a number: any difference means a different corpus answered,
// which is the question the cache needs answered. Ordering would require the app
// to understand a scheme the corpus build owns, and would silently return "not
// stale" the first time that scheme changed — a failure that shows as guidance
// nobody refreshes.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/data/repositories/drift_management_tips_repository.dart';
import 'package:visiosoil_app/core/data/repositories/management_tips_repository.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';

void main() {
  group('the column records what answered', () {
    late AppDatabase db;
    late DriftManagementTipsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DriftManagementTipsRepository(db);
    });

    tearDown(() async => db.close());

    ManagementTipsResult result({String? corpusVersion}) =>
        ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: const [ManagementTip(text: 'Mantenha cobertura.', citations: [])],
          sources: const [],
          disclaimer: 'Orientação consultiva.',
          model: 'corpus:${'x'}',
          retrievedAt: DateTime.utc(2026, 9, 10),
          corpusVersion: corpusVersion,
        );

    Future<String?> columnFor(String uuid) async {
      final rows = await db
          .customSelect(
            "SELECT corpus_version FROM management_tips "
            "WHERE record_uuid = '$uuid'",
          )
          .get();
      return rows.single.read<String?>('corpus_version');
    }

    test('upsert_writes_the_corpus_version_from_the_result', () async {
      await repo.upsert('rec-1', result(corpusVersion: '2026.09.1'));

      expect(await columnFor('rec-1'), '2026.09.1');
    });

    test('upsert_writes_null_when_the_result_has_no_version', () async {
      // This is the absent-corpus result SPEC 0068 produces while the app holds
      // no corpus. A placeholder here would make it look answered.
      await repo.upsert('rec-1', result());

      expect(await columnFor('rec-1'), isNull);
    });

    test('read_reports_the_cached_version', () async {
      await repo.upsert('rec-1', result(corpusVersion: '2026.09.1'));

      final cached = await repo.getCached('rec-1');

      expect(cached, isNotNull);
      expect(cached!.corpusVersion, '2026.09.1');
      expect(cached.result.status, ManagementTipsStatus.grounded);
    });

    test('read_of_an_absent_row_is_null', () async {
      expect(await repo.getCached('nobody'), isNull);
    });

    test('payload_and_column_agree_after_a_round_trip', () async {
      await repo.upsert('rec-1', result(corpusVersion: '2026.09.1'));

      final cached = await repo.getCached('rec-1');

      expect(cached!.result.corpusVersion, cached.corpusVersion);
    });

    test('the_existing_read_still_returns_the_result_alone', () async {
      await repo.upsert('rec-1', result(corpusVersion: '2026.09.1'));

      expect(await repo.getByRecordUuid('rec-1'), isNotNull);
    });
  });

  group('the staleness rule', () {
    CachedManagementTips cached(String? version) => CachedManagementTips(
          result: ManagementTipsResult(
            status: ManagementTipsStatus.insufficientEvidence,
            tips: const [],
            sources: const [],
            disclaimer: 'x',
            model: 'corpus:none',
            retrievedAt: DateTime.utc(2026, 9, 10),
            corpusVersion: version,
          ),
          corpusVersion: version,
        );

    test('a_row_is_stale_when_the_versions_differ', () {
      expect(cached('2026.09.1').isStaleAgainst('2026.10.1'), isTrue);
    });

    test('a_row_is_fresh_when_the_versions_match', () {
      expect(cached('2026.09.1').isStaleAgainst('2026.09.1'), isFalse);
    });

    test('a_null_cached_version_is_stale_against_any_corpus', () {
      // What closes the wart SPEC 0068 left on purpose: a row written while the
      // app held no corpus refreshes itself the moment one arrives, instead of
      // showing "no coverage" for a region that is now covered.
      expect(cached(null).isStaleAgainst('2026.09.1'), isTrue);
    });

    test('a_null_cached_version_is_not_stale_when_no_corpus_is_held', () {
      // With nothing to compare against, nothing is out of date — otherwise the
      // app would report every row stale forever while it holds no corpus.
      expect(cached(null).isStaleAgainst(null), isFalse);
    });

    test('a_version_is_stale_when_the_app_holds_no_corpus_to_match_it', () {
      expect(cached('2026.09.1').isStaleAgainst(null), isTrue);
    });

    test('staleness_does_not_order_versions', () {
      // A cached version that sorts *after* the current one is still stale: the
      // rule is difference, not age.
      expect(cached('2026.10.1').isStaleAgainst('2026.09.1'), isTrue);
    });
  });
}
