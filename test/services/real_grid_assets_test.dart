// End-to-end over the real artifacts: IBGE shapefile → the Python rasteriser →
// packed bytes → this app's reader → a `SiteKey`.
//
// The grids are build products and git-ignored, so this test **skips when they
// are absent** rather than failing in CI. What it proves when they are present
// is the one thing no unit test can: that the two sides of the format agree on
// bytes a machine actually produced, not on bytes a fixture builder wrote.
//
// Build them with `python -m src.build_grids` from `corpus/` and copy the two
// `.bin` files into `assets/corpus/`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/region/grid_site_resolver.dart';
import 'package:visiosoil_app/models/site_key.dart';

void main() {
  final clayFile = File('assets/corpus/clay-activity-grid.bin');
  final biomeFile = File('assets/corpus/biome-grid.bin');
  final present = clayFile.existsSync() && biomeFile.existsSync();
  final skip = present
      ? false
      : 'the real grids are build products; see corpus/README.md';

  group('the real grids', () {
    late GridSiteResolver resolver;

    setUp(() {
      if (!present) return;
      resolver = GridSiteResolver(
        clayActivityGrid: PackedGrid.parse(clayFile.readAsBytesSync()),
        biomeGrid: PackedGrid.parse(biomeFile.readAsBytesSync()),
      );
    });

    test('they parse and name their source maps', () {
      final clay = PackedGrid.parse(clayFile.readAsBytesSync());
      final biome = PackedGrid.parse(biomeFile.readAsBytesSync());

      expect(clay.kind, GridKind.clayActivity);
      expect(biome.kind, GridKind.biome);
      expect(clay.sourceId, contains('ibge'));
      expect(biome.sourceId, contains('ibge'));
      // Brazil's bounding box at 0.1 degrees.
      expect(clay.rows, 400);
      expect(clay.cols, 400);
      expect(clay.cellMilliDegrees, 100);
    }, skip: skip);

    test('a coordinate in the Cerrado resolves to the Cerrado', () async {
      // Brasília.
      final key = await resolver.resolve(latitude: -15.78, longitude: -47.93);

      expect(key.biome, Biome.cerrado);
    }, skip: skip);

    test('a coordinate in the Amazon resolves to the Amazon', () async {
      // Manaus.
      final key = await resolver.resolve(latitude: -3.10, longitude: -60.02);

      expect(key.biome, Biome.amazonia);
    }, skip: skip);

    test('a coordinate in the Caatinga resolves to the Caatinga', () async {
      // Petrolina.
      final key = await resolver.resolve(latitude: -9.39, longitude: -40.50);

      expect(key.biome, Biome.caatinga);
    }, skip: skip);

    test('a coordinate in the Pampa resolves to the Pampa', () async {
      // Bagé.
      final key = await resolver.resolve(latitude: -31.33, longitude: -54.11);

      expect(key.biome, Biome.pampa);
    }, skip: skip);

    test('the Cerrado plateau resolves a low-activity clay', () async {
      // Brasília again: deeply weathered Latossolo country, which is the whole
      // premise of the `Argilosa|tb_oxidic` cell.
      final key = await resolver.resolve(latitude: -15.78, longitude: -47.93);

      expect(key.clayActivity, ClayActivity.tbOxidic);
      expect(key.substanceIsGeneric, isFalse);
    }, skip: skip);

    test('a coordinate in the Atlantic resolves to nothing, not to a guess',
        () async {
      final key = await resolver.resolve(latitude: -20.0, longitude: -36.0);

      expect(key.biome, isNull);
      expect(key.clayActivity, isNull);
      expect(key.substanceIsGeneric, isTrue);
    }, skip: skip);
  });
}
