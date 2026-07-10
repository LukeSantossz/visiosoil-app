import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';

void main() {
  group('Formatters.timestamp', () {
    test('formats a valid ISO timestamp with the "às" connector', () {
      expect(
        Formatters.timestamp('2026-04-01T14:30:00'),
        '01/04/2026 às 14:30',
      );
    });

    test('zero-pads single-digit day, month, hour and minute', () {
      expect(
        Formatters.timestamp('2026-01-02T03:04:00'),
        '02/01/2026 às 03:04',
      );
    });

    test('returns the raw input unchanged when parsing fails', () {
      expect(Formatters.timestamp('not-a-date'), 'not-a-date');
    });
  });

  group('Formatters.timestampCompact', () {
    test('formats a valid ISO timestamp without the "às" connector', () {
      expect(
        Formatters.timestampCompact('2026-04-01T14:30:00'),
        '01/04/2026 14:30',
      );
    });

    test('zero-pads single-digit day, month, hour and minute', () {
      expect(
        Formatters.timestampCompact('2026-01-02T03:04:00'),
        '02/01/2026 03:04',
      );
    });

    test('returns the raw input unchanged when parsing fails', () {
      expect(Formatters.timestampCompact('not-a-date'), 'not-a-date');
    });
  });

  group('Formatters.coordinates', () {
    test('formats latitude and longitude with six decimals', () {
      expect(
        Formatters.coordinates(-23.550520, -46.633308),
        '-23.550520, -46.633308',
      );
    });

    test('pads shorter values to six decimal places', () {
      expect(Formatters.coordinates(1.5, -2.25), '1.500000, -2.250000');
    });
  });
}
