// docs/studies/ml/ is a durable archive of run verdicts, and one of them is
// withdrawn. Its README says which is which, so every document in it is
// listed there (SPEC 0254).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('studies_ml_index_lists_every_document', () {
    const directory = 'docs/studies/ml';
    final index = File('$directory/README.md');
    final listed = index.existsSync() ? index.readAsStringSync() : '';

    final missing = Directory(directory)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.md') && name != 'README.md')
        .where((name) => !listed.contains('](./$name)'))
        .toList()
      ..sort();

    expect(missing, isEmpty);
  });
}
