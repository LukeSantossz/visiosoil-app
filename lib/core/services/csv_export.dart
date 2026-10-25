import 'package:visiosoil_app/models/soil_record.dart';

/// CSV boundary: optional private fields never enter an unselected column.
abstract final class CsvExport {
  static String render(
    List<SoilRecord> records, {
    required bool includeDate,
    required bool includeLocation,
  }) {
    final rows = <List<String>>[
      [
        'Classe',
        'Confiança',
        if (includeDate) 'Data e hora',
        if (includeLocation) ...['Latitude', 'Longitude'],
      ],
      for (final record in records)
        [
          record.textureClass ?? '',
          record.confidenceScore?.toString() ?? '',
          if (includeDate) record.timestamp,
          if (includeLocation) ...[
            record.latitude?.toStringAsFixed(2) ?? '',
            record.longitude?.toStringAsFixed(2) ?? '',
          ],
        ],
    ];
    return '${rows.map((row) => row.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _escape(String value) {
    // Prefix executable spreadsheet cells, but keep numeric coordinates numeric.
    final trimmed = value.trimLeft();
    if (trimmed.isNotEmpty &&
        '=+@-'.contains(trimmed[0]) &&
        double.tryParse(value) == null) {
      value = "'$value";
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
