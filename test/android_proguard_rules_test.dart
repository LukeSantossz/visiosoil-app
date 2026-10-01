import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the R8 release-config for the auth stack (#69): the ProGuard keep rules
/// and the CI checks that exercise them.
///
/// The release build enables R8 shrinking. Tink (via `flutter_secure_storage`)
/// and Google Play Services auth (via `google_sign_in`) are partly loaded by
/// reflection R8 cannot see, so `-keep` rules protect their classes and members.
/// The rules are defensive today — the dependencies' own consumer rules already
/// retain the classes — but this guards against them, and the CI checks that
/// would catch a regression, being silently dropped.
void main() {
  final rules = File('android/app/proguard-rules.pro').readAsStringSync();
  final ci = File('.github/workflows/ci.yml').readAsStringSync();

  group('proguard keep rules', () {
    test('keeps_tink_classes_for_secure_storage', () {
      expect(
        rules.contains('-keep class com.google.crypto.tink.** { *; }'),
        isTrue,
        reason: 'the Tink keep rule is missing; R8 could strip the '
            'reflectively-accessed key managers on the '
            'flutter_secure_storage path',
      );
    });

    test('keeps_play_services_auth_classes_for_google_sign_in', () {
      expect(
        rules.contains('-keep class com.google.android.gms.auth.** { *; }'),
        isTrue,
        reason: 'the google_sign_in Play Services auth keep rule is missing',
      );
    });
  });

  group('ci release checks', () {
    // Assert executable command tokens, not tokens that also appear in comments,
    // so the guard fails when the actual check step is removed.
    test('build_job_verifies_auth_class_definitions_in_the_release_dex', () {
      expect(
        ci.contains('-name dexdump'),
        isTrue,
        reason: 'the dexdump DEX-definition inspection step is gone',
      );
      expect(
        ci.contains('Lcom/google/crypto/tink/') &&
            ci.contains('Lcom/google/android/gms/auth/'),
        isTrue,
        reason: 'the DEX class-definition checks for the auth classes are gone; '
            'a stripped auth class would no longer fail the release build',
      );
    });

    test('build_job_builds_and_uploads_the_release_app_bundle', () {
      // SPEC 0102 (#270): Play takes a bundle, so CI builds one on every
      // change. It stays debug-signed in CI; the signer is printed, not
      // asserted, and the command carries no store opt-in for #271 to gate on.
      expect(
        ci.contains('run: flutter build appbundle --release'),
        isTrue,
        reason: 'the build job no longer builds the release app bundle',
      );
      expect(
        ci.contains('keytool -printcert -jarfile '
            'build/app/outputs/bundle/release/app-release.aab'),
        isTrue,
        reason: 'the build job no longer prints the bundle signer',
      );
      expect(
        ci.contains('name: release-aab') &&
            ci.contains('path: build/app/outputs/bundle/release/app-release.aab'),
        isTrue,
        reason: 'the build job no longer uploads the bundle as release-aab',
      );
    });

    test('has_a_release_boot_smoke_job_that_runs_the_apk', () {
      expect(
        ci.contains('reactivecircus/android-emulator-runner'),
        isTrue,
        reason: 'the boot smoke job is missing; the release APK would build '
            'but never run in CI',
      );
      expect(
        ci.contains('adb install -r apk/app-release.apk') &&
            ci.contains('adb shell pidof com.visiosoil.app') &&
            ci.contains('logcat -d --pid='),
        isTrue,
        reason: 'the smoke job no longer installs the release APK, checks the '
            'app process is alive, and scans its PID log for a startup crash',
      );
    });

    test('smoke_boots_the_release_on_api_34_35_and_36', () {
      // SPEC 0103 (#289): targeting 35 enforces edge-to-edge and targeting 36
      // makes predictive back the default, so the boot runs on each, and on 34
      // as the floor it has proven since #69. Read the smoke job alone, so a
      // matrix elsewhere cannot satisfy it. A Windows checkout reads CRLF.
      final yaml = ci.replaceAll('\r\n', '\n');
      final start = yaml.indexOf('\n  smoke:\n');
      expect(start, isNot(-1), reason: 'the smoke job is missing');
      final end = yaml.indexOf(RegExp(r'\n  [a-z][a-z-]*:\n'), start + 1);
      final smoke = yaml.substring(start, end == -1 ? yaml.length : end);

      expect(
        smoke,
        contains('api-level: [34, 35, 36]'),
        reason: 'the smoke matrix no longer lists API 34, 35 and 36',
      );
      expect(
        smoke,
        contains(r'api-level: ${{ matrix.api-level }}'),
        reason: 'the emulator no longer boots the matrix version',
      );
      expect(
        smoke,
        contains('fail-fast: false'),
        reason: 'one version failing would cancel the others before they report',
      );
    });
  });
}
