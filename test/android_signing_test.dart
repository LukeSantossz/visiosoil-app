import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android release-signing wiring (#110).
///
/// Release APKs must be signed from an untracked `android/key.properties`
/// keystore rather than the debug key, with the setup documented in the README
/// and no secret material tracked. This test guards the Gradle wiring, the
/// `.gitignore` exclusions, and the documentation against regressing.
void main() {
  final gradle =
      File('android/app/build.gradle.kts').readAsStringSync();
  final gitignore = File('.gitignore').readAsStringSync();
  final readme = File('README.md').readAsStringSync();

  test('gradle_reads_key_properties_for_release_signing', () {
    expect(
      gradle,
      contains('key.properties'),
      reason: 'build.gradle.kts must source release signing from key.properties',
    );
  });

  test('gradle_defines_a_release_signing_config', () {
    expect(
      gradle.contains('create("release")') ||
          gradle.contains('signingConfigs.getByName("release")'),
      isTrue,
      reason: 'a release signingConfig must exist and be used by the release '
          'build type',
    );
  });

  test('gitignore_excludes_keystore_and_key_properties', () {
    expect(gitignore, contains('key.properties'));
    expect(gitignore, contains('*.jks'));
    expect(gitignore, contains('*.keystore'));
  });

  test('readme_documents_keystore_setup', () {
    expect(
      readme,
      contains('key.properties'),
      reason: 'README must document the key.properties setup',
    );
    expect(
      readme.toLowerCase(),
      contains('keytool'),
      reason: 'README must document keystore generation with keytool',
    );
  });
}
