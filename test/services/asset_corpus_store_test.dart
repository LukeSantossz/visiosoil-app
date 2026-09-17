// Loading the bundled corpus and the two grids.
//
// The rule that matters here is the one separating two absences: a bundle
// **without** the asset is a normal state — Lane B has not shipped content, and
// the app says there is no coverage. An asset that **is** present and does not
// parse is a build defect, and swallowing it would ship guidance-shaped silence.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/region/corpus_grid_assets.dart';
import 'package:visiosoil_app/core/services/research/asset_corpus_store.dart';
import 'package:visiosoil_app/models/site_key.dart';

/// The smallest thing that behaves like an asset bundle: a map of key to bytes.
/// Mirrors `InferenceService`'s injected `ModelAssetLoader` rather than reaching
/// for the real `rootBundle`, so no test depends on `assets/corpus/` being
/// populated — which it is not, and will not be until Lane B ships.
class FakeAssetBundle {
  FakeAssetBundle(this.assets);

  final Map<String, Uint8List> assets;
  int loads = 0;

  Future<Uint8List?> load(String key) async {
    loads++;
    return assets[key];
  }
}

void main() {
  Uint8List bytesOf(String path) => File(path).readAsBytesSync();

  Uint8List corpusBytes() => bytesOf('test/fixtures/corpus/corpus.json');

  group('the corpus asset', () {
    test('an_absent_corpus_asset_loads_as_no_corpus', () async {
      final bundle = FakeAssetBundle({});
      final store = AssetCorpusStore(loadAsset: bundle.load);

      expect(await store.current(), isNull);
    });

    test('a_present_corpus_asset_is_parsed', () async {
      final bundle = FakeAssetBundle({
        AssetCorpusStore.corpusAssetKey: corpusBytes(),
      });
      final store = AssetCorpusStore(loadAsset: bundle.load);

      final corpus = await store.current();

      expect(corpus, isNotNull);
      expect(corpus!.corpusVersion, 'fixture-2026.09.1');
      expect(corpus.substance, isNotEmpty);
    });

    test('fetched_at_is_the_corpus_built_at', () async {
      final bundle = FakeAssetBundle({
        AssetCorpusStore.corpusAssetKey: corpusBytes(),
      });

      final corpus = await AssetCorpusStore(loadAsset: bundle.load).current();

      // For a snapshot that shipped with the binary, the honest answer for
      // "when was this retrieved" is when it was built, not when the app booted.
      expect(corpus!.fetchedAt, DateTime.utc(2026, 9, 10));
    });

    test('a_malformed_corpus_asset_is_loud', () async {
      final bundle = FakeAssetBundle({
        AssetCorpusStore.corpusAssetKey:
            Uint8List.fromList(utf8.encode('{ not json')),
      });
      final store = AssetCorpusStore(loadAsset: bundle.load);

      expect(
        store.current(),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(AssetCorpusStore.corpusAssetKey),
        )),
      );
    });

    test('a_corpus_violating_its_contract_is_loud', () async {
      // Valid JSON, invalid corpus: no disclaimer at all.
      final bundle = FakeAssetBundle({
        AssetCorpusStore.corpusAssetKey: Uint8List.fromList(
          utf8.encode(jsonEncode({'corpusVersion': 'x', 'substance': {}})),
        ),
      });

      expect(
        AssetCorpusStore(loadAsset: bundle.load).current(),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(AssetCorpusStore.corpusAssetKey),
        )),
      );
    });

    test('a_corpus_without_a_built_at_is_refused', () async {
      final json =
          jsonDecode(utf8.decode(corpusBytes())) as Map<String, dynamic>
            ..remove('builtAt');
      final bundle = FakeAssetBundle({
        AssetCorpusStore.corpusAssetKey:
            Uint8List.fromList(utf8.encode(jsonEncode(json))),
      });

      expect(
        AssetCorpusStore(loadAsset: bundle.load).current(),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('builtAt'),
        )),
      );
    });

    test('the_corpus_is_parsed_once_per_process', () async {
      final bundle = FakeAssetBundle({
        AssetCorpusStore.corpusAssetKey: corpusBytes(),
      });
      final store = AssetCorpusStore(loadAsset: bundle.load);

      final first = await store.current();
      final second = await store.current();

      expect(bundle.loads, 1);
      expect(identical(first, second), isTrue);
    });

    test('an_absent_corpus_is_not_retried_on_every_read', () async {
      final bundle = FakeAssetBundle({});
      final store = AssetCorpusStore(loadAsset: bundle.load);

      await store.current();
      await store.current();

      expect(bundle.loads, 1);
    });
  });

  group('the grid assets', () {
    Map<String, Uint8List> gridAssets() => {
          CorpusGridAssets.clayActivityKey:
              bytesOf('test/fixtures/corpus/grids/clay-activity-grid.bin'),
          CorpusGridAssets.biomeKey:
              bytesOf('test/fixtures/corpus/grids/biome-grid.bin'),
        };

    test('absent_grids_leave_their_key_parts_null', () async {
      final bundle = FakeAssetBundle({});

      final resolver = await CorpusGridAssets.resolver(loadAsset: bundle.load);
      final key = await resolver.resolve(
        latitude: -22.95,
        longitude: -46.85,
        address: 'Rua X, Campinas, São Paulo',
      );

      expect(key.clayActivity, isNull);
      expect(key.biome, isNull);
      // The unit still resolves: it comes from the address, not from a grid.
      expect(key.unit, 'BR-SP');
    });

    test('present_grids_resolve_their_key_parts', () async {
      final bundle = FakeAssetBundle(gridAssets());

      final resolver = await CorpusGridAssets.resolver(loadAsset: bundle.load);
      final key = await resolver.resolve(latitude: -22.95, longitude: -46.85);

      expect(key.clayActivity, ClayActivity.tbOxidic);
      expect(key.biome, Biome.cerrado);
    });

    test('a_malformed_grid_is_loud', () async {
      final bundle = FakeAssetBundle({
        CorpusGridAssets.clayActivityKey:
            Uint8List.fromList(List.filled(40, 0)),
      });

      expect(
        CorpusGridAssets.resolver(loadAsset: bundle.load),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(CorpusGridAssets.clayActivityKey),
        )),
      );
    });

    test('one_grid_present_and_one_absent_is_a_valid_resolver', () async {
      final bundle = FakeAssetBundle({
        CorpusGridAssets.clayActivityKey:
            bytesOf('test/fixtures/corpus/grids/clay-activity-grid.bin'),
      });

      final resolver = await CorpusGridAssets.resolver(loadAsset: bundle.load);
      final key = await resolver.resolve(latitude: -22.95, longitude: -46.85);

      expect(key.clayActivity, ClayActivity.tbOxidic);
      expect(key.biome, isNull);
    });
  });

  group('what ships in the bundle', () {
    test('the_corpus_directory_is_declared_in_pubspec', () {
      // Without the declaration every load fails at runtime while every test
      // above passes, because the tests inject a bundle.
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(pubspec, contains('- assets/corpus/'));
    });

    test('the_assets_stay_under_the_ceiling', () {
      final dir = Directory('assets/corpus');
      expect(dir.existsSync(), isTrue, reason: 'assets/corpus/ must exist');

      final total = dir
          .listSync()
          .whereType<File>()
          .fold<int>(0, (sum, f) => sum + f.lengthSync());

      expect(
        total,
        lessThanOrEqualTo(500 * 1024),
        reason: 'assets/corpus/ holds $total bytes against a 500 KB ceiling; '
            'exceeding it is a decision a spec states, not an accident',
      );
    });
  });
}
