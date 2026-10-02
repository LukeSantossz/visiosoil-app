// `AppColors` holds the light palette's values. A widget that reads it stays
// light under the dark theme, so only the theme layer may name it (SPEC 0107).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no_widget_reads_the_fixed_palette', () {
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = file.path.replaceAll('\\', '/');
      if (path.startsWith('lib/core/theme/')) continue;
      // Comments stripped, so a mention in prose is not a read.
      final source = file
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      if (RegExp(r'\bAppColors\b').hasMatch(source)) offenders.add(path);
    }

    expect(offenders, isEmpty,
        reason: 'read colours through context.palette instead');
  });
}
