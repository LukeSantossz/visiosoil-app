import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the declared Dart SDK floor against the resolved lockfile (#153): the
/// `environment.sdk` constraint in `pubspec.yaml` must admit an SDK at least as
/// new as the minimum `pubspec.lock` resolved, so any toolchain satisfying the
/// declared constraint can also use the committed resolution. When
/// `shared_preferences` landed (#49), the lock moved to `dart ">=3.12.0"` while
/// the declared floor stayed at `^3.11.0`, leaving the two inconsistent.
/// Packs a `major.minor.patch` triple into one monotonically comparable int
/// (each component is well under 1000), so full lower-bound versions can be
/// compared without missing a patch-level mismatch.
int _versionCode(Match m) =>
    int.parse(m.group(1)!) * 1000000 +
    int.parse(m.group(2)!) * 1000 +
    int.parse(m.group(3)!);

void main() {
  test('declared sdk floor is consistent with the resolved lockfile', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();

    final declared = RegExp(r'sdk:\s*\^(\d+)\.(\d+)\.(\d+)').firstMatch(pubspec);
    expect(
      declared,
      isNotNull,
      reason: 'could not find an `sdk: ^x.y.z` constraint in pubspec.yaml',
    );

    final resolved = RegExp(r'dart:\s*">=(\d+)\.(\d+)\.(\d+)').firstMatch(lock);
    expect(
      resolved,
      isNotNull,
      reason: 'could not find a `dart: ">=x.y.z"` floor in pubspec.lock sdks',
    );

    final declaredVersion =
        '${declared!.group(1)}.${declared.group(2)}.${declared.group(3)}';
    final resolvedVersion =
        '${resolved!.group(1)}.${resolved.group(2)}.${resolved.group(3)}';

    // Compare the complete lower bounds (major.minor.patch), not just the minor,
    // so a patch-only lockfile bump (e.g. lock >=3.12.1 vs pubspec ^3.12.0) is
    // still caught — 3.12.0 satisfies the pubspec but cannot use that lock.
    expect(
      _versionCode(declared),
      greaterThanOrEqualTo(_versionCode(resolved)),
      reason: 'pubspec.yaml declares Dart ^$declaredVersion but pubspec.lock '
          'resolved dart >=$resolvedVersion; the declared floor must admit the '
          'resolved minimum so `pub get` can use the committed lockfile',
    );
  });
}
