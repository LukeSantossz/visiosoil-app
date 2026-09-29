import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';

/// The model's class list used to exist in two languages, and until SPEC 0048
/// nothing compared them. Since SPEC 0083 the app declares no class list of its
/// own: it labels a classification with the shipped contract's classes. So the
/// comparison is now between `ml/config.yaml`, which the training reads, and
/// `assets/models/spec.json`, which the release fit wrote from it. A release
/// fitted under another class list would compile, pass both suites, and
/// mislabel every result.
///
/// The file is parsed by pattern rather than with a YAML package: adding a
/// dependency to the app for one test in `test/standards/` is a production-tree
/// cost for a test-tree benefit, and `durable_numbering_test.dart` and
/// `readme_adr_index_test.dart` already read repository files this way.
void main() {
  group('the shipped contract carries the configured classes', () {
    late List<String> configured;

    setUpAll(() {
      configured = _classesFromConfig(File('ml/config.yaml').readAsStringSync());
    });

    test('the_shipped_contract_classes_are_the_configured_classes', () {
      final parsed = parseDescriptorContract(
        File('assets/models/spec.json').readAsStringSync(),
      );
      expect(parsed.cause, isNull);
      expect(parsed.contract!.classes, configured);
    });

    // Anti-vacuity. If the `classes:` block gains an anchor, a merge key or a
    // nested form, the parser stops matching and the comparison above would
    // hold between two empty lists. This is what fails instead.
    test('the class list test is not vacuous', () {
      expect(configured, isNotEmpty);
      expect(configured.length, greaterThanOrEqualTo(2));
      expect(
        _classesFromConfig('classes:\n  - "Only"\n'),
        ['Only'],
        reason: 'the parser no longer reads a well-formed classes block',
      );
      expect(
        _classesFromConfig('model:\n  architecture: "mobilenetv2"\n'),
        isEmpty,
        reason: 'the parser matches a block that is not the class list',
      );
    });
  });
}

/// The entries of the top-level `classes:` block, in order.
///
/// Stops at the first line that is neither a list entry nor a comment, so a
/// later block's entries cannot be read as classes.
List<String> _classesFromConfig(String source) {
  final lines = const LineSplitter().convert(source);
  final start = lines.indexWhere((line) => line.trimRight() == 'classes:');
  if (start == -1) return const [];

  final entry = RegExp(r'''^\s+-\s*["']?([^"'#]+?)["']?\s*$''');
  final classes = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final match = entry.firstMatch(line);
    if (match == null) break;
    classes.add(match.group(1)!);
  }
  return classes;
}
