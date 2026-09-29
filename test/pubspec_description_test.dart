import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the package description against the Flutter template's placeholder
/// (#280), which it carried until SPEC 0087.
void main() {
  test('pubspec_description_is_not_the_template_default', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^description:\s*"?(.*?)"?\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(
      match,
      isNotNull,
      reason: 'pubspec.yaml declares no description',
    );
    final description = match!.group(1)!.trim();
    expect(description, isNotEmpty);
    expect(description, isNot('A new Flutter project.'));
  });
}
