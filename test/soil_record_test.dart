import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/soil_record.dart';

void main() {
  group('SoilRecord', () {
    final ts = DateTime.utc(2026, 1, 1).toIso8601String();

    test('hasCoordinates is false when latitude or longitude is null', () {
      final a = SoilRecord(imagePath: '/a.jpg', timestamp: ts);
      final b = SoilRecord(
        imagePath: '/b.jpg',
        latitude: 1.0,
        timestamp: ts,
      );
      expect(a.hasCoordinates, isFalse);
      expect(b.hasCoordinates, isFalse);
    });

    test('hasCoordinates is true when both coordinates are set', () {
      final r = SoilRecord(
        imagePath: '/c.jpg',
        latitude: -23.5,
        longitude: -46.6,
        timestamp: ts,
      );
      expect(r.hasCoordinates, isTrue);
    });

    test('hasValidAddress rejects placeholder and empty values', () {
      final noAddr = SoilRecord(imagePath: '/d.jpg', timestamp: ts);
      final placeholder = SoilRecord(
        imagePath: '/e.jpg',
        address: 'Localização não disponível',
        timestamp: ts,
      );
      expect(noAddr.hasValidAddress, isFalse);
      expect(placeholder.hasValidAddress, isFalse);
    });
  });
}
