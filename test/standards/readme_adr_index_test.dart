// Guards the rule in .standards/docs/standards/INDEX.md that the README's
// Engineering Decisions section indexes the ADRs: every record under docs/adr/
// must be reachable from the README.
//
// SPEC 0010 already stated this as an acceptance criterion
// (`readme_indexes_every_adr`) and nothing enforced it, so the index drifted
// from seven ADRs to fourteen while the README still linked seven. A criterion
// that only a reader can check is a criterion that stops being true silently;
// this is SPEC 0036 making it a test, in the shape SPEC 0013 used for the
// durable-numbering rule.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _adrDir = 'docs/adr';
const _readmePath = 'README.md';

final _adrFile = RegExp(r'(\d{4})-[a-z0-9-]+\.md$');

// --- Pure rules, exercised directly below so each one is tested rather than
// merely observed against whatever the repository happens to contain today. ---

/// The ADR numbers carried by [filenames].
Set<String> adrNumbersIn(Iterable<String> filenames) {
  final numbers = <String>{};
  for (final name in filenames) {
    final match = _adrFile.firstMatch(name.replaceAll(r'\', '/'));
    if (match != null) numbers.add(match.group(1)!);
  }
  return numbers;
}

/// The ADR numbers [readme] links to, by any `docs/adr/NNNN-...` reference.
///
/// Matches the path rather than the link text: the Engineering Decisions table
/// names a decision in prose and carries the record as a markdown link, and the
/// number in that path is what ties the row to a record. Whether the path
/// resolves is [danglingAdrLinks]' question, not this one.
Set<String> linkedAdrNumbers(String readme) {
  final numbers = <String>{};
  for (final match in RegExp(r'docs/adr/(\d{4})-').allMatches(readme)) {
    numbers.add(match.group(1)!);
  }
  return numbers;
}

/// Numbers present under [_adrDir] that [readme] does not link, sorted.
List<String> unlinkedAdrNumbers(Iterable<String> filenames, String readme) {
  final missing = adrNumbersIn(filenames).difference(linkedAdrNumbers(readme));
  return missing.toList()..sort();
}

/// Numbers [readme] links that no record under [_adrDir] carries, sorted.
///
/// The inverse of [unlinkedAdrNumbers], and the reason the index cannot be
/// satisfied cheaply: a link to `docs/adr/0099-invented.md` would otherwise
/// count as indexing a record that does not exist.
List<String> danglingAdrLinks(Iterable<String> filenames, String readme) {
  final dangling = linkedAdrNumbers(readme).difference(adrNumbersIn(filenames));
  return dangling.toList()..sort();
}

void main() {
  group('the rules', () {
    test('adrNumbersIn reads the number from a record filename', () {
      expect(
        adrNumbersIn(['0001-decision.md', '0014-another-one.md', 'README.md']),
        {'0001', '0014'},
      );
    });

    test('linkedAdrNumbers finds a link anywhere in the document', () {
      const readme = '| A decision ([ADR 0009](docs/adr/0009-some-slug.md)) |';
      expect(linkedAdrNumbers(readme), {'0009'});
    });

    test('unlinkedAdrNumbers reports a record the README does not link', () {
      // The mutation this guard exists to catch: a record is added and the
      // index is not. Without this case the repository assertion below could
      // pass vacuously on an empty difference it never computes.
      expect(
        unlinkedAdrNumbers(
          ['0001-first.md', '0002-second.md'],
          '[ADR 0001](docs/adr/0001-first.md)',
        ),
        ['0002'],
      );
    });

    test('unlinkedAdrNumbers reports nothing when every record is linked', () {
      expect(
        unlinkedAdrNumbers(
          ['0001-first.md', '0002-second.md'],
          '[a](docs/adr/0001-first.md) [b](docs/adr/0002-second.md)',
        ),
        isEmpty,
      );
    });

    test('danglingAdrLinks reports a link to a record that does not exist', () {
      // Without this the index could be satisfied by a link that resolves to
      // nothing, which reads as coverage and is the opposite of it.
      expect(
        danglingAdrLinks(
          ['0001-first.md'],
          '[a](docs/adr/0001-first.md) [b](docs/adr/0099-invented.md)',
        ),
        ['0099'],
      );
    });

    test('danglingAdrLinks reports nothing when every link resolves', () {
      expect(
        danglingAdrLinks(['0001-first.md'], '[a](docs/adr/0001-first.md)'),
        isEmpty,
      );
    });
  });

  group('this repository', () {
    test('readme_indexes_every_adr', () {
      final adrs = Directory(_adrDir)
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList();
      expect(
        adrNumbersIn(adrs),
        isNotEmpty,
        reason: 'no ADR was found under $_adrDir; the guard would pass '
            'vacuously',
      );

      final readme = File(_readmePath).readAsStringSync();
      expect(
        unlinkedAdrNumbers(adrs, readme),
        isEmpty,
        reason: 'every ADR must be linked from $_readmePath, per '
            '.standards/docs/standards/INDEX.md and SPEC 0010',
      );
    });

    test('readme_links_no_absent_adr', () {
      final adrs = Directory(_adrDir)
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList();
      final readme = File(_readmePath).readAsStringSync();
      expect(
        danglingAdrLinks(adrs, readme),
        isEmpty,
        reason: 'an ADR link in $_readmePath points at a record that does not '
            'exist under $_adrDir',
      );
    });
  });
}
