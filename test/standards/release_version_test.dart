// The README's Project Status names the version the pubspec declares
// (SPEC 0259). A build reports the pubspec's version in Settings and in the
// error report it shares, so the README must not describe another one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the_readme_names_the_pubspec_version', () {
    final declared = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+\s*$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(declared, isNotNull, reason: 'pubspec.yaml declares no version');

    final lines = File(
      'README.md',
    ).readAsLinesSync().map((line) => line.trim()).toList();
    final heading = lines.indexOf('## Project Status');
    expect(heading, isNot(-1), reason: 'README.md has no Project Status');
    final status = lines
        .skip(heading + 1)
        .firstWhere((line) => line.isNotEmpty);

    expect(status, contains('`${declared!.group(1)}`'));
  });
}
