// Every spinner is the shared LoadingIndicator, and every app bar the shared
// VisioAppBar, outside the stated exceptions (SPEC 0123).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dart files under lib/ that construct [pattern], by repository path.
List<String> _constructing(RegExp pattern) => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where((file) => pattern.hasMatch(file.readAsStringSync()))
    .map((file) => file.path.replaceAll(r'\', '/'))
    .toList()
  ..sort();

void main() {
  test('one_loading_presentation', () {
    expect(
      _constructing(RegExp(r'\bCircularProgressIndicator\(')),
      ['lib/core/widgets/loading_indicator.dart'],
    );
  });

  test('app_bar_is_shared', () {
    // A SliverAppBar or a VisioAppBar does not match: the name must start at
    // a word boundary. Preview's black-canvas bars went with SPEC 0124.
    expect(
      _constructing(RegExp(r'(?<![A-Za-z])AppBar\(')),
      ['lib/core/widgets/visio_app_bar.dart'],
    );
  });
}
