// The key the corpus is looked up by, and the rule that it is always a value.
//
// `SiteKey` returns a value rather than a nullable even when nothing resolved:
// an unresolved coordinate yields a key whose fields are null, not a null key,
// so a caller cannot forget to handle the case (research-agent.md §19.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/site_key.dart';

void main() {
  group('SiteKey', () {
    test('unresolved_site_is_a_value_not_a_null', () {
      const key = SiteKey.unresolved();

      expect(key.country, 'BR');
      expect(key.clayActivity, isNull);
      expect(key.unit, isNull);
      expect(key.biome, isNull);
    });

    test('substance_is_generic_when_clay_activity_is_absent', () {
      const resolved = SiteKey(clayActivity: ClayActivity.tbOxidic);
      const unresolved = SiteKey.unresolved();

      expect(resolved.substanceIsGeneric, isFalse);
      expect(unresolved.substanceIsGeneric, isTrue);
    });

    test('equal_keys_compare_equal', () {
      const a = SiteKey(
        clayActivity: ClayActivity.intermediate,
        unit: 'BR-SP',
        biome: Biome.cerrado,
      );
      const b = SiteKey(
        clayActivity: ClayActivity.intermediate,
        unit: 'BR-SP',
        biome: Biome.cerrado,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('wire names', () {
    test('clay_activity_wire_names_match_the_corpus_key', () {
      expect(
        ClayActivity.values.map((e) => e.wireName),
        ['tb_oxidic', 'intermediate', 'ta_less_weathered'],
      );
    });

    test('biome_wire_names_match_the_ibge_list', () {
      expect(
        Biome.values.map((e) => e.wireName),
        [
          'amazonia',
          'cerrado',
          'mata_atlantica',
          'caatinga',
          'pampa',
          'pantanal',
        ],
      );
    });

    test('land_use_wire_names_match_the_five_values', () {
      expect(
        LandUse.values.map((e) => e.wireName),
        [
          'native_vegetation',
          'pasture',
          'annual_crop',
          'perennial_or_forest',
          'exposed_or_degraded',
        ],
      );
    });

    test('unknown_wire_name_resolves_to_null', () {
      expect(ClayActivity.fromWire('smectitic'), isNull);
      expect(Biome.fromWire('tundra'), isNull);
      expect(LandUse.fromWire('aquaculture'), isNull);
    });

    test('known_wire_name_round_trips', () {
      for (final value in ClayActivity.values) {
        expect(ClayActivity.fromWire(value.wireName), value);
      }
      for (final value in Biome.values) {
        expect(Biome.fromWire(value.wireName), value);
      }
      for (final value in LandUse.values) {
        expect(LandUse.fromWire(value.wireName), value);
      }
    });
  });
}
