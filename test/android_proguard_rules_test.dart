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
    test('build_job_verifies_auth_classes_survive_r8_in_the_dex', () {
      expect(
        ci.contains('Lcom/google/crypto/tink/') &&
            ci.contains('Lcom/google/android/gms/auth/'),
        isTrue,
        reason: 'the DEX-retention check is missing; a stripped auth class '
            'would no longer fail the release build',
      );
    });

    test('has_a_release_boot_smoke_job_on_an_emulator', () {
      expect(
        ci.contains('reactivecircus/android-emulator-runner'),
        isTrue,
        reason: 'the boot smoke job is missing; the release APK would build '
            'but never run in CI',
      );
      expect(
        ci.contains('FATAL EXCEPTION'),
        isTrue,
        reason: 'the smoke job no longer fails on a startup crash',
      );
    });
  });
}
