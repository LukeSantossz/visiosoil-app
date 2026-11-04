// The top level of docs/ says what each part is for, so a new document goes
// under one of these entries rather than beside them (SPEC 0253). Plans got
// their own entry when the implementation maps left studies/ (SPEC 0254).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _layout = {
  'README.md',
  'adr',
  'agents',
  'design',
  'guides',
  'plans',
  'specs',
  'studies',
};

void main() {
  test('docs_top_level_is_the_declared_layout', () {
    final entries = Directory('docs')
        .listSync()
        .map((e) => e.path.replaceAll('\\', '/').split('/').last)
        .toSet();

    expect(entries, _layout);
  });
}
