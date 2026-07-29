import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the declared Dart SDK floor against the resolved lockfile (#153): the
/// `environment.sdk` constraint in `pubspec.yaml` must admit an SDK at least as
/// new as the minimum `pubspec.lock` resolved, so any toolchain satisfying the
/// declared constraint can also use the committed resolution. When
/// `shared_preferences` landed (#49), the lock moved to `dart ">=3.12.0"` while
/// the declared floor stayed at `^3.11.0`, leaving the two inconsistent.
void main() {
  test('declared sdk floor is consistent with the resolved lockfile', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();

    final declared = RegExp(r'sdk:\s*\^3\.(\d+)\.\d+').firstMatch(pubspec);
    expect(
      declared,
      isNotNull,
      reason: 'could not find an `sdk: ^3.x.y` constraint in pubspec.yaml',
    );

    final resolved = RegExp(r'dart:\s*">=3\.(\d+)\.\d+').firstMatch(lock);
    expect(
      resolved,
      isNotNull,
      reason: 'could not find a `dart: ">=3.x.y"` floor in pubspec.lock sdks',
    );

    final declaredMinor = int.parse(declared!.group(1)!);
    final resolvedMinor = int.parse(resolved!.group(1)!);

    expect(
      declaredMinor,
      greaterThanOrEqualTo(resolvedMinor),
      reason: 'pubspec.yaml declares Dart 3.$declaredMinor but pubspec.lock '
          'resolved dart >=3.$resolvedMinor; the declared floor must admit the '
          'resolved minimum so `pub get` can use the committed lockfile',
    );
  });
}
