import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';

import 'field_session_report.dart';

/// Reports a folder of field photographs (SPEC 0170): every JPEG in the folder
/// `VISIOSOIL_PHOTOS` names, through the descriptor path the app runs. Skipped
/// when the variable is unset, so `flutter test` is unchanged. A folder of
/// `<class>/<sample>/` folders is scored against its labels, and
/// `VISIOSOIL_EXPORT` writes each measured photograph at the canonical scale
/// for the Python side (SPEC 0174).
///
/// ```sh
/// VISIOSOIL_PHOTOS=<folder> [VISIOSOIL_EXPORT=<dir>] flutter test test/field_session/field_session_test.dart
/// ```
void main() {
  final folder = Platform.environment['VISIOSOIL_PHOTOS'];
  final export = Platform.environment['VISIOSOIL_EXPORT'];

  test(
    'reports the field session',
    () async {
      final photographs = await readFieldSession(folder!, exportDir: export);
      final classes = parseDescriptorContract(
        File('assets/models/spec.json').readAsStringSync(),
      ).contract!.classes;
      // The report is this test's output.
      // ignore: avoid_print
      print(fieldSessionReport(photographs, classes: classes));
    },
    skip: folder == null ? 'VISIOSOIL_PHOTOS is not set' : false,
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
