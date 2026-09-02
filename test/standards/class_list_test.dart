import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/soil_texture_labels.dart';

/// The model's class list exists in two languages, and until SPEC 0048 nothing
/// compared them. `ml/config.yaml` is what the training reads and what the
/// exported model's output order comes from; `SoilTextureLabels.ordered` is what
/// the app maps that output onto. A change to one and not the other compiles,
/// passes both suites, and mislabels every result.
///
/// The file is parsed by pattern rather than with a YAML package: adding a
/// dependency to the app for one test in `test/standards/` is a production-tree
/// cost for a test-tree benefit, and `durable_numbering_test.dart` and
/// `readme_adr_index_test.dart` already read repository files this way.
void main() {
  group('the class list agrees across both languages', () {
    late List<String> configured;

    setUpAll(() {
      configured = _classesFromConfig(File('ml/config.yaml').readAsStringSync());
    });

    test('dart label list matches the configured classes', () {
      expect(SoilTextureLabels.ordered, configured);
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
