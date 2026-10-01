import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android manifest: the backup policy (#111) and the app name
/// (#280).
///
/// The cleartext SQLite database and the captured `soil_images/` originals are
/// confidential field data that must not leave the device. `allowBackup="false"`
/// disables Auto Backup and `adb backup` on API <= 30, but on Android 12+ it does
/// not disable device-to-device transfer — that path is governed by
/// `dataExtractionRules`. Both, plus a full-exclude rules file, are required to
/// cover every API level; this test guards against any of them being dropped.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final rulesFile =
      File('android/app/src/main/res/xml/data_extraction_rules.xml');

  test('android_manifest_labels_the_app_visiosoil', () {
    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest);
    expect(
      application,
      isNotNull,
      reason: '<application> is missing from AndroidManifest.xml',
    );
    expect(
      application!.group(0),
      contains('android:label="VisioSoil"'),
      reason: 'the launcher, recent apps and permission dialogs show this '
          'label; it must be VisioSoil, not the template placeholder',
    );
  });

  // Play filters the listing by the hardware a manifest requires, declared or
  // implied by a permission. VisioSoil needs a camera; location and autofocus
  // are optional, since a record saves without coordinates and the camera app
  // handles focus (SPEC 0100).
  String? usesFeature(String name) => RegExp(
        '<uses-feature\\b[^>]*android:name="${RegExp.escape(name)}"[^>]*/>',
      ).firstMatch(manifest)?.group(0);

  test('manifest_requires_the_camera', () {
    final feature = usesFeature('android.hardware.camera');
    expect(feature, isNotNull,
        reason: 'android.hardware.camera is not declared');
    expect(feature, isNot(contains('android:required="false"')),
        reason: 'capture is camera-only, so the camera is required');
  });

  test('manifest_does_not_require_location_hardware', () {
    expect(usesFeature('android.hardware.location'),
        contains('android:required="false"'),
        reason: 'the location permissions imply android.hardware.location; '
            'a record saves without coordinates, so it is not required');
  });

  test('manifest_does_not_require_camera_autofocus', () {
    expect(usesFeature('android.hardware.camera.autofocus'),
        contains('android:required="false"'),
        reason: 'the camera app handles focus; fixed-focus phones must not '
            'be filtered out');
  });

  test('manifest_declares_allow_backup_false', () {
    expect(
      manifest.contains('android:allowBackup="false"'),
      isTrue,
      reason:
          'android:allowBackup="false" is missing from AndroidManifest.xml; '
          'confidential data would be backup-eligible on API <= 30',
    );
  });

  test('manifest_references_data_extraction_rules', () {
    expect(
      manifest
          .contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      isTrue,
      reason:
          'android:dataExtractionRules is missing; on Android 12+ device-to-'
          'device transfer is not covered by allowBackup alone',
    );
  });

  test('rules_exclude_all_domains_from_cloud_backup_and_device_transfer', () {
    expect(
      rulesFile.existsSync(),
      isTrue,
      reason: 'res/xml/data_extraction_rules.xml is missing',
    );
    final rules = rulesFile.readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(
      rules,
      contains('<device-transfer>'),
      reason: 'device-transfer must be excluded to block Android 12+ D2D copy',
    );
    // path="/" is the filesystem root, not the domain directory, so it excludes
    // nothing; a whole-domain exclude omits the path.
    expect(
      rules.contains('path="/"'),
      isFalse,
      reason: 'path="/" does not match a domain directory; omit path instead',
    );
    for (final domain in const [
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
    ]) {
      expect(
        rules,
        contains('domain="$domain"'),
        reason: 'domain "$domain" must be excluded from backups',
      );
    }
  });
}
