import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android backup policy in `android/app/src/main/AndroidManifest.xml`
/// (#111).
///
/// The cleartext SQLite database and the captured `soil_images/` originals are
/// confidential field data that must not be copied off-device by Auto Backup or
/// `adb backup`. `android:allowBackup="false"` is the master switch that disables
/// every backup path; this test guards against it being dropped or flipped back
/// to the implicit `true` default.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('manifest_declares_allow_backup_false', () {
    expect(
      manifest.contains('android:allowBackup="false"'),
      isTrue,
      reason:
          'android:allowBackup="false" is missing from AndroidManifest.xml; '
          'confidential data would be backup-eligible by default',
    );
  });
}
