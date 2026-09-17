// The resolver that turns a coordinate and an address into a `SiteKey`, on the
// device. Resolving server-side would require sending the coordinate, which is
// the egress the whole design exists to remove (research-agent.md §5.2).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/region/grid_site_resolver.dart';
import 'package:visiosoil_app/models/site_key.dart';

import '../support/packed_grid_builder.dart';

void main() {
  // A 3x3 lattice at 0.1 degrees whose south-west corner sits at 23.0 S, 47.0 W
  // — inside São Paulo state, so the fixture reads as a real place rather than
  // an abstract one.
  PackedGridBuilder clayGrid({List<int>? cells}) => PackedGridBuilder(
        kind: GridKind.clayActivity,
        cellMilliDegrees: 100,
        originLatMilliDegrees: -23000,
        originLonMilliDegrees: -47000,
        rows: 3,
        cols: 3,
        sourceId: 'fixture-soil-map',
        cells: cells ??
            const [
              0, 1, 1, // row 0, southernmost: unresolved, tb_oxidic, tb_oxidic
              2, 2, 3, // row 1
              3, 3, 0, // row 2, northernmost
            ],
      );

  PackedGridBuilder biomeGrid({List<int>? cells}) => PackedGridBuilder(
        kind: GridKind.biome,
        cellMilliDegrees: 100,
        originLatMilliDegrees: -23000,
        originLonMilliDegrees: -47000,
        rows: 3,
        cols: 3,
        sourceId: 'fixture-biome-map',
        cells: cells ??
            const [
              2, 2, 2, // cerrado
              3, 3, 3, // mata_atlantica
              0, 3, 3,
            ],
      );

  GridSiteResolver resolver({
    PackedGridBuilder? clay,
    PackedGridBuilder? biome,
  }) =>
      GridSiteResolver(
        clayActivityGrid: PackedGrid.parse((clay ?? clayGrid()).build()),
        biomeGrid: PackedGrid.parse((biome ?? biomeGrid()).build()),
      );

  group('grid reading', () {
    test('header_is_parsed_from_the_artifact', () {
      final grid = PackedGrid.parse(clayGrid().build());

      expect(grid.kind, GridKind.clayActivity);
      expect(grid.cellMilliDegrees, 100);
      expect(grid.rows, 3);
      expect(grid.cols, 3);
      expect(grid.sourceId, 'fixture-soil-map');
    });

    test('lookup_is_an_index_from_latitude_and_longitude', () {
      final grid = PackedGrid.parse(clayGrid().build());

      // Row 0 (south edge -23.0), column 1 (west edge -46.9): value 1.
      expect(grid.valueAt(latitude: -22.95, longitude: -46.85), 1);
      // Row 2, column 0: value 3.
      expect(grid.valueAt(latitude: -22.75, longitude: -46.95), 3);
    });

    test('coordinate_outside_the_lattice_reads_unresolved', () {
      final grid = PackedGrid.parse(clayGrid().build());

      expect(grid.valueAt(latitude: -10.0, longitude: -46.9), 0);
      expect(grid.valueAt(latitude: -22.95, longitude: -60.0), 0);
    });

    test('bad_magic_is_refused_by_name', () {
      final bytes = clayGrid().build();
      bytes[0] = 0x58; // X

      expect(
        () => PackedGrid.parse(bytes),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('magic'),
        )),
      );
    });

    test('truncated_payload_is_refused_by_name', () {
      final full = clayGrid().build();
      final truncated = full.sublist(0, full.length - 2);

      expect(
        () => PackedGrid.parse(truncated),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('payload'),
        )),
      );
    });

    test('unknown_format_version_is_refused_rather_than_guessed', () {
      final bytes = clayGrid().build();
      bytes[4] = 9;

      expect(
        () => PackedGrid.parse(bytes),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('version'),
        )),
      );
    });
  });

  group('resolving a site', () {
    test('resolver_reads_both_grids', () async {
      final key = await resolver().resolve(
        latitude: -22.95,
        longitude: -46.85,
        address: 'Rua X, Campinas, São Paulo',
      );

      expect(key.clayActivity, ClayActivity.tbOxidic);
      expect(key.biome, Biome.cerrado);
      expect(key.unit, 'BR-SP');
      expect(key.country, 'BR');
    });

    test('one_grid_resolving_while_the_other_does_not_is_a_valid_key',
        () async {
      // Row 2, column 0: clay activity 3, biome 0.
      final key = await resolver().resolve(
        latitude: -22.75,
        longitude: -46.95,
      );

      expect(key.clayActivity, ClayActivity.taLessWeathered);
      expect(key.biome, isNull);
      expect(key.substanceIsGeneric, isFalse);
    });

    test('unresolved_coordinate_yields_all_null_site_key', () async {
      final key = await resolver().resolve(latitude: null, longitude: null);

      expect(key, const SiteKey.unresolved());
      expect(key.substanceIsGeneric, isTrue);
    });

    test('out_of_country_coordinate_resolves_to_no_unit', () async {
      // Buenos Aires: outside both grids and outside the unit table.
      final key = await resolver().resolve(
        latitude: -34.6,
        longitude: -58.4,
        address: 'Avenida Corrientes, Buenos Aires, Buenos Aires',
      );

      expect(key.clayActivity, isNull);
      expect(key.biome, isNull);
      expect(key.unit, isNull);
    });

    test('a_value_outside_the_enum_reads_as_unresolved', () async {
      // A grid written by a newer build that added a fourth family.
      final key = await resolver(
        clay: clayGrid(cells: const [9, 9, 9, 9, 9, 9, 9, 9, 9]),
      ).resolve(latitude: -22.95, longitude: -46.85);

      expect(key.clayActivity, isNull);
      expect(key.substanceIsGeneric, isTrue);
    });
  });

  group('federative unit from the address the app already has', () {
    test('state_name_maps_to_its_iso_code', () {
      expect(GridSiteResolver.unitFromAddress('Rua X, Campinas, São Paulo'),
          'BR-SP');
      expect(
        GridSiteResolver.unitFromAddress('Av Y, Belo Horizonte, Minas Gerais'),
        'BR-MG',
      );
      expect(GridSiteResolver.unitFromAddress('Z, Goiânia, Goiás'), 'BR-GO');
    });

    test('accents_and_case_do_not_change_the_answer', () {
      expect(GridSiteResolver.unitFromAddress('a, b, SAO PAULO'), 'BR-SP');
      expect(GridSiteResolver.unitFromAddress('a, b, goias'), 'BR-GO');
      expect(GridSiteResolver.unitFromAddress('a, b, ceara'), 'BR-CE');
    });

    test('bare_uf_abbreviation_is_accepted', () {
      expect(GridSiteResolver.unitFromAddress('Rua X, Campinas, SP'), 'BR-SP');
    });

    test('unknown_or_absent_address_yields_no_unit', () {
      expect(GridSiteResolver.unitFromAddress(null), isNull);
      expect(GridSiteResolver.unitFromAddress(''), isNull);
      expect(GridSiteResolver.unitFromAddress('Localização não disponível'),
          isNull);
      expect(GridSiteResolver.unitFromAddress('Calle 1, Lima, Lima'), isNull);
    });

    test('every_iso_code_is_a_brazilian_federative_unit', () {
      expect(GridSiteResolver.federativeUnitCodes.length, 27);
      for (final code in GridSiteResolver.federativeUnitCodes) {
        expect(code, startsWith('BR-'));
        expect(code.length, 5);
      }
    });
  });

  group('the committed fixture grids', () {
    // The fixtures are bytes, so nothing about them is readable in a diff. This
    // test is what makes them reviewable: it states what they contain and fails
    // if they drift. Regenerate by running this test and writing the builder's
    // output, which is exactly what the assertions below describe.
    test('fixture_grids_match_the_builder_that_documents_them', () {
      final clay = File('test/fixtures/corpus/grids/clay-activity-grid.bin');
      final biome = File('test/fixtures/corpus/grids/biome-grid.bin');

      expect(clay.existsSync(), isTrue, reason: 'fixture clay grid is missing');
      expect(biome.existsSync(), isTrue, reason: 'fixture biome grid is missing');
      expect(clay.readAsBytesSync(), clayGrid().build());
      expect(biome.readAsBytesSync(), biomeGrid().build());
    });

    test('fixture_grids_parse_and_resolve', () {
      final grid = PackedGrid.parse(
        File('test/fixtures/corpus/grids/clay-activity-grid.bin')
            .readAsBytesSync(),
      );

      expect(grid.sourceId, 'fixture-soil-map');
      expect(grid.valueAt(latitude: -22.95, longitude: -46.85), 1);
    });
  });
}
