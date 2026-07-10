// Tests for [ShareContentBuilder]: the pure, I/O-free content used by the share
// flow — the text caption and the composed PNG card. The [ShareService] flow
// around it (temp-file write, share, cleanup) is covered in share_service_test.dart.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/share_content_builder.dart';
import 'package:visiosoil_app/models/soil_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SoilRecord record({
    String? textureClass = 'Argilosa',
    double? confidenceScore = 0.91,
    double? latitude = -23.5,
    double? longitude = -46.6,
    String? address = 'São Paulo, SP',
  }) {
    return SoilRecord(
      imagePath: '/img.jpg',
      latitude: latitude,
      longitude: longitude,
      address: address,
      timestamp: DateTime.utc(2026, 1, 2, 14, 30).toIso8601String(),
      textureClass: textureClass,
      confidenceScore: confidenceScore,
    );
  }

  group('ShareContentBuilder.caption', () {
    test('includes class, confidence and date by default', () {
      final text = ShareContentBuilder.caption(record());

      expect(text, contains('Argilosa'));
      expect(text, contains('91.0%'));
      expect(text, contains('02/01/2026'));
    });

    test('omits location by default', () {
      final text = ShareContentBuilder.caption(record());

      expect(text, isNot(contains('Local:')));
      expect(text, isNot(contains('Coordenadas:')));
    });

    test('includes location only when opted in', () {
      final text = ShareContentBuilder.caption(record(), includeLocation: true);

      expect(text, contains('Local: São Paulo, SP'));
      expect(text, contains('Coordenadas:'));
    });

    test('omits fields that are missing or unavailable even when opted in', () {
      final text = ShareContentBuilder.caption(
        record(
          textureClass: null,
          confidenceScore: null,
          address: null,
          latitude: null,
          longitude: null,
        ),
        includeLocation: true,
      );

      expect(text, isNot(contains('Classe:')));
      expect(text, isNot(contains('Local:')));
      expect(text, isNot(contains('Coordenadas:')));
      expect(text, contains('Data:'));
    });
  });

  group('ShareContentBuilder.composeCard', () {
    test('returns a non-empty PNG taller than the source photo', () async {
      final source = img.Image(width: 200, height: 150);
      img.fill(source, color: img.ColorRgb8(120, 100, 80));
      final photoBytes = Uint8List.fromList(img.encodePng(source));

      final cardBytes =
          await ShareContentBuilder.composeCard(record(), photoBytes);

      expect(cardBytes, isNotEmpty);
      final decoded = img.decodePng(cardBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1080);
      // The footer band is drawn below the scaled photo (150 * 1080/200 = 810).
      expect(decoded.height, greaterThan(810));
    });
  });
}
