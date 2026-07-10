import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android backup policy (#111).
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
