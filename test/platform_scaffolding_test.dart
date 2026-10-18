import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the platforms the app targets: Android and iOS only (SPEC 0168).
///
/// The desktop and web scaffolding was Flutter's template, which nothing
/// built, tested or deployed. It is read from git rather than from the disk,
/// so a local build's leftovers under a removed directory do not fail it.
void main() {
  test('only_the_mobile_platforms_are_scaffolded', () {
    final result = Process.runSync(
      'git',
      ['ls-files', '--', 'macos', 'linux', 'windows', 'web'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).trim(), isEmpty,
        reason: 'files are tracked under a platform the app does not target');

    final platforms = RegExp(r'^\s*- platform: (\S+)', multiLine: true)
        .allMatches(File('.metadata').readAsStringSync())
        .map((match) => match.group(1))
        .toList();
    expect(platforms, ['root', 'android', 'ios']);
  });
}
