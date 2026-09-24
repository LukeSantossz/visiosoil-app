// Acceptance criteria for the Dart patch descriptors (SPEC 0077).
//
// Each test name matches an acceptance criterion in
// `docs/specs/0077-describe-a-patch-in-dart-under-a-cross-language-golden.md`.
// The golden is written by `ml/scripts/generate_descriptor_golden.py` from
// `ml/src/descriptors.py`, and `ml/tests/test_descriptor_golden.py` asserts that
// Python still reproduces it, so a divergence on either side fails the other
// side's suite.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_descriptors.dart';

const _goldenPath = 'test/fixtures/descriptors/golden.json';

/// SPEC 0030's tolerance, which SPEC 0077 adopts.
Matcher _near(double want) => closeTo(want, want.abs() * 1e-9 + 1e-12);

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    final file = File(_goldenPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$_goldenPath is missing. Regenerate it with '
          '`cd ml && python scripts/generate_descriptor_golden.py`.',
    );
    golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  List<Map<String, dynamic>> entries(String key) =>
      (golden[key] as List<dynamic>).cast<Map<String, dynamic>>();

  test('dart_descriptors_match_the_golden', () {
    final names = (golden['feature_names'] as List<dynamic>).cast<String>();
    final fixtures = entries('fixtures');
    expect(fixtures, isNotEmpty);
    for (final fixture in fixtures) {
      final name = fixture['name'] as String;
      final pixels = base64Decode(fixture['pixels'] as String);
      final features = describePatch(
        pixels,
        fixture['height'] as int,
        fixture['width'] as int,
      );
      final expected = (fixture['features'] as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList();
      expect(features.length, expected.length, reason: name);
      for (var index = 0; index < expected.length; index++) {
        expect(features[index], _near(expected[index]),
            reason: '$name.${names[index]}');
      }
    }
  });

  test('dart_feature_names_match_python', () {
    expect(descriptorFeatureNames, golden['feature_names']);
  });

  test('dart_band_edges_match_python', () {
    for (final shape in entries('band_edges')) {
      final edges = descriptorBandEdges(
        shape['height'] as int,
        shape['width'] as int,
      );
      final expected = (shape['edges'] as List<dynamic>)
          .map((value) => (value as num).toDouble())
          .toList();
      expect(edges.length, expected.length);
      for (var index = 0; index < expected.length; index++) {
        expect(edges[index], _near(expected[index]),
            reason: '${shape['height']}x${shape['width']} edge $index');
      }
    }
  });

  test('dart_band_map_matches_python', () {
    for (final shape in entries('band_edges')) {
      final height = shape['height'] as int;
      final width = shape['width'] as int;
      final expected = Int8List.fromList(
        base64Decode(shape['bands'] as String),
      );
      final actual = descriptorBandMap(height, width);
      expect(actual.length, height * width);
      final wrong = <int>[
        for (var bin = 0; bin < actual.length; bin++)
          if (actual[bin] != expected[bin]) bin,
      ];
      expect(wrong, isEmpty, reason: '${height}x$width bins in another band');
    }
  });

  test('a_patch_with_no_band_is_refused', () {
    expect(
      () => describePatch(Uint8List(16), 4, 4),
      throwsA(isA<ArgumentError>().having(
          (error) => '${error.message}', 'message', contains('band'))),
    );
    expect(describePatch(Uint8List(25), 5, 5).length, 26);
  });

  test('a_patch_below_the_minimum_side_is_refused', () {
    expect(() => describePatch(Uint8List(6), 2, 3), throwsArgumentError);
  });

  test('a_buffer_of_the_wrong_length_is_refused', () {
    expect(() => describePatch(Uint8List(24), 5, 5), throwsArgumentError);
  });
}
