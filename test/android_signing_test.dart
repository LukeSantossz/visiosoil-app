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

  test('gradle_defines_and_uses_a_release_signing_config', () {
    // Both the definition and the use are required: an unused release config
    // while the release build still signs with debug must not pass.
    expect(
      gradle,
      contains('create("release")'),
      reason: 'a release signingConfig must be defined from key.properties',
    );
    expect(
      gradle,
      contains('signingConfigs.getByName("release")'),
      reason: 'the release build type must use the release signingConfig',
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
