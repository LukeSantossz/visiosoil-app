import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('register_font_licenses_exposes_inter_license', () async {
    registerFontLicenses();

    final license = await LicenseRegistry.licenses.firstWhere(
      (entry) => entry.packages.contains('Inter'),
    );

    expect(
      license.paragraphs.map((paragraph) => paragraph.text).join('\n'),
      contains('SIL OPEN FONT LICENSE'),
    );
  });
}
