// Acceptance criteria for the Dart half of the descriptor contract (SPEC 0079).
//
// Each test name matches an acceptance criterion in
// `docs/specs/0079-the-descriptor-contract-and-the-arithmetic-that-reads-it.md`.
// The golden is written by `ml/scripts/generate_contract_golden.py` from the
// real `fit_probe` and `descriptor_contract`, and `ml/tests/test_contract.py`
// holds the writer to the pipeline it describes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';

const _goldenPath = 'test/fixtures/contract/golden.json';

/// SPEC 0030's tolerance, which SPEC 0079 adopts.
Matcher _near(double want) => closeTo(want, want.abs() * 1e-9 + 1e-12);

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    final file = File(_goldenPath);
    expect(
      file.existsSync(),
      isTrue,
      reason: '$_goldenPath is missing. Regenerate it with '
          '`cd ml && python scripts/generate_contract_golden.py`.',
    );
    golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  /// A fresh, mutable copy of the golden contract.
  Map<String, dynamic> contract() =>
      jsonDecode(jsonEncode(golden['contract'])) as Map<String, dynamic>;

  ClassificationFailureCause? causeOf(Object document) =>
      parseDescriptorContract(
        document is String ? document : jsonEncode(document),
      ).cause;

  Map<String, dynamic> section(Map<String, dynamic> document, String key) =>
      document[key] as Map<String, dynamic>;

  test('the_golden_contract_parses', () {
    final parsed = parseDescriptorContract(jsonEncode(golden['contract']));
    expect(parsed.cause, isNull);
    expect(parsed.contract!.classes, golden['contract']['classes']);
    expect(parsed.contract!.modelVersion, 'golden');
  });

  test('dart_distribution_matches_the_golden', () {
    final parsed = parseDescriptorContract(jsonEncode(golden['contract']));
    final photographs =
        (golden['photographs'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(photographs, isNotEmpty);
    for (final photograph in photographs) {
      final patches = [
        for (final row in photograph['patches'] as List<dynamic>)
          Float64List.fromList(
            (row as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
          ),
      ];
      final distribution = parsed.contract!.distribution(patches);
      final expected = (photograph['distribution'] as List<dynamic>)
          .map((v) => (v as num).toDouble())
          .toList();
      expect(distribution.length, expected.length);
      for (var index = 0; index < expected.length; index++) {
        expect(distribution[index], _near(expected[index]),
            reason: '${photograph['name']}[$index]');
      }
    }
  });

  group('malformed_contract_yields_contract_malformed', () {
    const malformed = ClassificationFailureCause.contractMalformed;

    test('text that is not a JSON object', () {
      expect(causeOf('{"spec_version": 2,'), malformed);
      expect(causeOf('[1, 2]'), malformed);
    });

    test('each required field removed', () {
      final required = <List<String>>[
        ['spec_version'],
        ['classifier'],
        ['model_version'],
        ['dataset_version'],
        ['classes'],
        ['geometry'],
        ['geometry', 'canonical_mm_per_px'],
        ['geometry', 'patch_px'],
        ['geometry', 'patch_stride_fraction'],
        ['geometry', 'min_patches'],
        ['descriptors'],
        for (final key in [
          'glcm_levels',
          'glcm_offsets',
          'lbp_points',
          'lbp_radius',
          'lbp_mapping',
          'spectral_bands',
          'min_cycles_per_patch',
          'features',
        ])
          ['descriptors', key],
        ['standardiser'],
        ['standardiser', 'mean'],
        ['standardiser', 'scale'],
        ['regression'],
        ['regression', 'coefficients'],
        ['regression', 'intercepts'],
        ['aggregation'],
      ];
      for (final path in required) {
        final document = contract();
        Map<String, dynamic> parent = document;
        for (final key in path.take(path.length - 1)) {
          parent = section(parent, key);
        }
        parent.remove(path.last);
        expect(causeOf(document), malformed, reason: path.join('.'));
      }
    });

    test('a wrong type', () {
      expect(causeOf(contract()..['classes'] = 'Arenosa'), malformed);
      expect(causeOf(contract()..['model_version'] = 3), malformed);
      final meanAsText = contract();
      (section(meanAsText, 'standardiser')['mean'] as List)[0] = 'x';
      expect(causeOf(meanAsText), malformed);
      final patchAsText = contract();
      section(patchAsText, 'geometry')['patch_px'] = '160';
      expect(causeOf(patchAsText), malformed);
    });

    test('a non-finite number', () {
      final document = contract();
      (section(document, 'standardiser')['mean'] as List)[0] = 12345.5;
      final text = jsonEncode(document).replaceFirst('12345.5', '1e999');
      expect(causeOf(text), malformed);
    });

    test('a scale of zero or below', () {
      for (final value in [0.0, -1.0]) {
        final document = contract();
        (section(document, 'standardiser')['scale'] as List)[3] = value;
        expect(causeOf(document), malformed, reason: '$value');
      }
    });

    test('an empty or duplicated class list', () {
      expect(causeOf(contract()..['classes'] = <String>[]), malformed);
      final duplicated = contract();
      (duplicated['classes'] as List)[1] = (duplicated['classes'] as List)[0];
      expect(causeOf(duplicated), malformed);
    });

    test('insane geometry', () {
      for (final entry in {
        'canonical_mm_per_px': 0.0,
        'patch_px': 0,
        'patch_stride_fraction': 1.5,
        'min_patches': 0,
      }.entries) {
        final document = contract();
        section(document, 'geometry')[entry.key] = entry.value;
        expect(causeOf(document), malformed, reason: entry.key);
      }
    });

    test('each length mismatch', () {
      void shorten(Map<String, dynamic> document, List<String> path) {
        Object? node = document;
        for (final key in path) {
          node = (node as Map<String, dynamic>)[key];
        }
        (node as List).removeLast();
      }

      for (final path in [
        ['standardiser', 'mean'],
        ['standardiser', 'scale'],
        ['regression', 'coefficients'],
        ['regression', 'intercepts'],
      ]) {
        final document = contract();
        shorten(document, path);
        expect(causeOf(document), malformed, reason: path.join('.'));
      }
      final shortRow = contract();
      ((section(shortRow, 'regression')['coefficients'] as List)[2] as List)
          .removeLast();
      expect(causeOf(shortRow), malformed, reason: 'a short coefficient row');
    });
  });

  group('unsupported_contract_yields_contract_unsupported', () {
    const unsupported = ClassificationFailureCause.contractUnsupported;

    test('another version, classifier or aggregation', () {
      expect(causeOf(contract()..['spec_version'] = 1), unsupported);
      expect(causeOf(contract()..['spec_version'] = 3), unsupported);
      expect(causeOf(contract()..['classifier'] = 'cnn'), unsupported);
      expect(causeOf(contract()..['aggregation'] = 'vote'), unsupported);
    });

    test('each changed descriptor fixed point', () {
      for (final entry in <String, Object>{
        'glcm_levels': 8,
        'glcm_offsets': [
          [0, 1],
          [1, 1],
          [-1, 0],
          [-1, -1],
        ],
        'lbp_points': 16,
        'lbp_radius': 2,
        'lbp_mapping': 'uniform',
        'spectral_bands': 6,
        'min_cycles_per_patch': 1.0,
      }.entries) {
        final document = contract();
        section(document, 'descriptors')[entry.key] = entry.value;
        expect(causeOf(document), unsupported, reason: entry.key);
      }
    });

    test('a reordered or renamed feature list', () {
      final reordered = contract();
      final features = section(reordered, 'descriptors')['features'] as List;
      final first = features[0];
      features[0] = features[1];
      features[1] = first;
      expect(causeOf(reordered), unsupported);

      final renamed = contract();
      (section(renamed, 'descriptors')['features'] as List)[5] = 'spectral.b1';
      expect(causeOf(renamed), unsupported);
    });
  });

  test('unknown_keys_are_ignored', () {
    final document = contract()
      ..['bands'] = {'per_class': {}}
      ..['comment'] = 'a later field';
    section(document, 'descriptors')['note'] = 1;
    section(document, 'geometry')['scale_reference'] = 'a4_sheet';
    expect(causeOf(document), isNull);
  });

  test('a_photograph_with_no_patch_is_refused', () {
    final parsed = parseDescriptorContract(jsonEncode(golden['contract']));
    expect(() => parsed.contract!.distribution([]), throwsArgumentError);
    expect(
      () => parsed.contract!.distribution([Float64List(25)]),
      throwsArgumentError,
    );
  });
}
