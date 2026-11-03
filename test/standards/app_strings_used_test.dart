// A constant in AppStrings that no screen reads looks like the source of some
// copy while the screen writes its own (SPEC 0252).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _stringsPath = 'lib/core/constants/app_strings.dart';

void main() {
  test('every_app_string_is_used', () {
    final names = RegExp(r'static const (?:String )?(\w+)\s*=')
        .allMatches(File(_stringsPath).readAsStringSync())
        .map((m) => m.group(1)!)
        .toList();
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              f.path.replaceAll('\\', '/') != _stringsPath,
        )
        .map((f) => f.readAsStringSync())
        .join('\n');

    final unused = names
        .where((n) => !RegExp('AppStrings\\.$n\\b').hasMatch(sources))
        .toList();

    expect(names, isNotEmpty);
    expect(unused, isEmpty, reason: 'delete the constant or read it');
  });
}
