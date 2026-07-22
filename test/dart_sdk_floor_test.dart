import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Dart SDK floor (#114): the `environment.sdk` constraint must admit
/// only Dart >= 3.11.0, so `pub get` cannot run on a toolchain vulnerable to
/// CVE-2026-27704 (a pub-cache symlink path traversal fixed in Dart 3.11.0).
void main() {
  test('dart_sdk_floor_is_at_least_3_11', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'sdk:\s*\^3\.(\d+)\.\d+').firstMatch(pubspec);
    expect(
      match,
      isNotNull,
      reason: 'could not find a `sdk: ^3.x.y` constraint in pubspec.yaml',
    );
    final minor = int.parse(match!.group(1)!);
    expect(
      minor,
      greaterThanOrEqualTo(11),
      reason: 'the Dart SDK floor must be >= 3.11.0 to exclude toolchains '
          'vulnerable to CVE-2026-27704',
    );
  });
}
