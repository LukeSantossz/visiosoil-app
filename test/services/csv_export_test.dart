import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/csv_export.dart';
import 'package:visiosoil_app/models/soil_record.dart';

void main() {
  const record = SoilRecord(
    imagePath: '',
    timestamp: '2026-10-24',
    textureClass: '=unsafe,"soil"',
    confidenceScore: .82,
    latitude: -17.79123,
    longitude: -50.92456,
  );
  test('exports_only_selected_columns_and_escapes_formulas', () {
    final csv = CsvExport.render(
      [record],
      includeDate: false,
      includeLocation: false,
    );
    expect(csv, contains('"Classe","Confiança"\r\n'));
    expect(csv, contains('"\'=unsafe,""soil"""'));
    expect(csv, isNot(contains('2026-10-24')));
    expect(csv, isNot(contains('-17.79')));
  });
  test('exports_selected_date_and_rounded_location', () {
    final csv = CsvExport.render(
      [record],
      includeDate: true,
      includeLocation: true,
    );
    expect(csv, contains('2026-10-24'));
    expect(csv, contains('-17.79'));
    expect(csv, isNot(contains('-17.79123')));
  });
}
