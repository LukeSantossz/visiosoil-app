import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS build job (#90): CI must compile the real iOS target so an
/// iOS-only platform-config break (like the missing reversed-client-id URL
/// scheme fixed in #66) fails the pipeline instead of merging green.
///
/// Asserts executable tokens scoped to the `build-ios` job, so the guard fails
/// if the job is removed or its runner/build/gate is weakened. Full-line YAML
/// comments are stripped first, so a matching token surviving only in a comment
/// cannot keep the guard green. `build-ios` is the file's last job, so its text
/// runs from `build-ios:` to end of file.
void main() {
  // Drop whole-line `#` comments so the assertions accept executable config only.
  final ci = File('.github/workflows/ci.yml')
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');

  group('ci ios build job', () {
    test('exists and compiles the iOS target with no signing on macOS', () {
      expect(
        ci.contains('build-ios:'),
        isTrue,
        reason: 'the build-ios job is missing; iOS is never compiled in CI',
      );

      final job = ci.substring(ci.indexOf('build-ios:'));

      expect(
        job.contains('runs-on: macos-latest'),
        isTrue,
        reason: 'build-ios must run on macos-latest — only macOS can run '
            'xcodebuild',
      );
      expect(
        job.contains('flutter build ios --release --no-codesign'),
        isTrue,
        reason: 'build-ios must run the real no-codesign iOS build; without it '
            'no iOS compile happens and config breaks stay invisible',
      );
    });

    test('is gated on analyze and test and installs dependencies first', () {
      expect(
        ci.contains('build-ios:'),
        isTrue,
        reason: 'the build-ios job is missing',
      );

      final job = ci.substring(ci.indexOf('build-ios:'));

      expect(
        job.contains('needs: [analyze, test]'),
        isTrue,
        reason: 'build-ios must be gated on analyze + test, like the Android '
            'build job',
      );
      expect(
        job.contains('flutter pub get'),
        isTrue,
        reason: 'build-ios must run flutter pub get before building',
      );
    });
  });
}
