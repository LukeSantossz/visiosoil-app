import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'field_session_report.dart';

/// Reports a folder of field photographs (SPEC 0170): every JPEG in the folder
/// `VISIOSOIL_PHOTOS` names, through the descriptor path the app runs. Skipped
/// when the variable is unset, so `flutter test` is unchanged.
///
/// ```sh
/// VISIOSOIL_PHOTOS=<folder> flutter test test/field_session/field_session_test.dart
/// ```
void main() {
  final folder = Platform.environment['VISIOSOIL_PHOTOS'];

  test(
    'reports the field session',
    () async {
      final photographs = await readFieldSession(folder!);
      // The report is this test's output.
      // ignore: avoid_print
      print(fieldSessionReport(photographs));
    },
    skip: folder == null ? 'VISIOSOIL_PHOTOS is not set' : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
