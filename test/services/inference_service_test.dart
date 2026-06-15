import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

void main() {
  ByteData bytesOfLength(int length) =>
      Uint8List.fromList(List<int>.filled(length, 1)).buffer.asByteData();

  group('InferenceService.initialize', () {
    test('returns true when the loader succeeds', () async {
      final service = InferenceService();
      final result = await service.initialize(
        assetLoader: (_) async => bytesOfLength(8),
        retryDelay: Duration.zero,
      );
      expect(result, isTrue);
      expect(service.isReady, isTrue);
    });

    test('retries transient failures then succeeds', () async {
      var calls = 0;
      final service = InferenceService();
      final result = await service.initialize(
        retryDelay: Duration.zero,
        assetLoader: (_) async {
          calls++;
          if (calls < 3) throw Exception('transient');
          return bytesOfLength(8);
        },
      );
      expect(result, isTrue);
      expect(calls, 3);
    });

    test('marks an empty model permanently unavailable', () async {
      var calls = 0;
      Future<ByteData> loader(String _) async {
        calls++;
        return bytesOfLength(0);
      }

      final service = InferenceService();
      final first = await service.initialize(
        assetLoader: loader,
        retryDelay: Duration.zero,
      );
      final second = await service.initialize(
        assetLoader: loader,
        retryDelay: Duration.zero,
      );

      expect(first, isFalse);
      expect(second, isFalse);
      expect(calls, 1); // empty model is permanent: loader not invoked again
    });

    test('allows a new attempt after transient failures exhaust', () async {
      var calls = 0;
      Future<ByteData> loader(String _) async {
        calls++;
        throw Exception('transient');
      }

      final service = InferenceService();
      final first = await service.initialize(
        assetLoader: loader,
        retryDelay: Duration.zero,
      );
      final callsAfterFirst = calls;
      final second = await service.initialize(
        assetLoader: loader,
        retryDelay: Duration.zero,
      );

      expect(first, isFalse);
      expect(second, isFalse);
      expect(callsAfterFirst, 3); // bounded attempts per call
      expect(calls, greaterThan(callsAfterFirst)); // not permanently locked
    });
  });

  group('InferenceService.resolveTextureLabel', () {
    test('returns the label for a valid index when the class count matches', () {
      expect(InferenceService.resolveTextureLabel(2, 5), 'Siltosa');
    });

    test('returns null when the class count mismatches the labels', () {
      expect(InferenceService.resolveTextureLabel(0, 3), isNull);
    });

    test('returns null for an out-of-range index', () {
      expect(InferenceService.resolveTextureLabel(7, 5), isNull);
    });
  });
}
