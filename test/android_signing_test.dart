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

  group('store bundle refuses the debug key', () {
    // SPEC 0111 (#271): the bundle's only consumer is Play, which rejects a
    // debug signature, so bundleRelease fails without key.properties unless
    // the named opt-out is set. The APK keeps SPEC 0004's fallback.
    const refusal =
        'android/key.properties not found; refusing to sign the release app bundle';

    test('bundle_release_refuses_the_debug_key_without_key_properties', () {
      expect(gradle, contains('if (!hasReleaseKeystore && !allowDebugBundle)'));
      expect(gradle, contains('gradle.taskGraph.whenReady'));
      expect(gradle, contains('allTasks.any { it.name == "bundleRelease" }'));
      expect(gradle, contains('throw GradleException('));
      expect(
        gradle,
        contains(refusal),
        reason: 'the refusal must name key.properties',
      );
    });

    test('debug_bundle_needs_the_named_opt_out', () {
      expect(
        gradle,
        contains(
          'val allowDebugBundle = '
          'System.getenv("VISIOSOIL_ALLOW_DEBUG_BUNDLE") == "true"',
        ),
      );
    });

    test('apk_release_still_falls_back_to_the_debug_key', () {
      expect(gradle, contains('signingConfigs.getByName("debug")'));
      expect(
        gradle,
        contains('signing the release build with the debug key.'),
        reason: 'the APK fallback must keep its warning (SPEC 0004)',
      );
      expect(
        'it.name =='.allMatches(gradle).length,
        1,
        reason: 'the refusal must match bundleRelease and no other task',
      );
      expect(gradle, isNot(contains('assembleRelease')));
    });

    test('build_job_proves_the_refusal_and_opts_out_for_its_bundle', () {
      // A Windows checkout reads CRLF.
      final ci = File('.github/workflows/ci.yml')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      String step(String name) {
        final start = ci.indexOf('      - name: $name\n');
        expect(start, isNot(-1), reason: 'the step "$name" is missing');
        final end = ci.indexOf('\n      - ', start + 1);
        return ci.substring(start, end == -1 ? ci.length : end);
      }

      final proof = step('Refuse the debug key for an unflagged bundle');
      expect(proof, contains('if flutter build appbundle --release'));
      expect(proof, contains('exit 1'));
      expect(proof, contains('grep -q "$refusal"'));
      expect(
        proof,
        isNot(contains('VISIOSOIL_ALLOW_DEBUG_BUNDLE')),
        reason: 'the proof must run without the opt-out',
      );

      final bundle = step('Build the release app bundle');
      expect(bundle, contains('VISIOSOIL_ALLOW_DEBUG_BUNDLE: "true"'));
      expect(
        'VISIOSOIL_ALLOW_DEBUG_BUNDLE:'.allMatches(ci).length,
        1,
        reason: 'only the bundle step may set the opt-out',
      );
      expect(
        ci.indexOf('- name: Refuse the debug key for an unflagged bundle'),
        lessThan(ci.indexOf('- name: Build the release app bundle')),
        reason: 'the proof runs before the flagged bundle build',
      );
    });
  });

  test('readme_documents_building_and_verifying_the_bundle', () {
    // SPEC 0102 (#270): the store takes the bundle, so the README shows how to
    // build it and how to read its signer, as it does for the APK.
    expect(readme, contains('flutter build appbundle --release'));
    expect(
      readme,
      contains(
        'keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab',
      ),
    );
  });
}
