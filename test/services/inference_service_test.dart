import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/services/inference_service.dart';

// Isolate entry points must be top-level (or static) so they can be sent to a
// spawned isolate; a closure capturing test state is not sendable.

/// Responds immediately with a result, standing in for a successful run.
void respondingEntry(InferenceRequest request) {
  request.responsePort.send(
    const InferenceResult(textureClass: 'Media', confidenceScore: 0.75),
  );
}

/// Keeps the isolate alive without ever responding, so the timeout fires with
/// a live isolate to kill — an entry point that simply returns would let the
/// isolate exit on its own and prove nothing.
void hangingEntry(InferenceRequest request) {
  ReceivePort(); // an open port keeps this isolate from terminating
}

/// Writes a marker, blocks, then overwrites it. `sleep` blocks the isolate
/// outright, so nothing cooperative can interrupt it: if the second write never
/// lands, the isolate was killed rather than merely abandoned.
///
/// [InferenceRequest.imagePath] carries the marker path — this entry point does
/// no inference, so the field is free to reuse as the test channel.
void markerEntry(InferenceRequest request) {
  final marker = File(request.imagePath);
  marker.writeAsStringSync('started');
  sleep(const Duration(milliseconds: 1500));
  marker.writeAsStringSync('started+finished');
}

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

  group('InferenceService.classify', () {
    Future<InferenceService> readyService() async {
      final service = InferenceService();
      await service.initialize(
        assetLoader: (_) async => bytesOfLength(8),
        retryDelay: Duration.zero,
      );
      return service;
    }

    test('returns the result the isolate sends back', () async {
      final service = await readyService();

      final result = await service.classify(
        '/unused.jpg',
        entryPoint: respondingEntry,
      );

      expect(result, isNotNull);
      expect(result!.textureClass, 'Media');
      expect(result.confidenceScore, 0.75);
    });

    test('returns null when the isolate exceeds the timeout', () async {
      final service = await readyService();

      final result = await service.classify(
        '/unused.jpg',
        timeout: const Duration(milliseconds: 100),
        entryPoint: hangingEntry,
      );

      expect(result, isNull);
    });

    test('kills the isolate on timeout so it stops working', () async {
      final dir = Directory.systemTemp.createTempSync('visiosoil_kill');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final marker = File(p.join(dir.path, 'marker.txt'));
      final service = await readyService();

      // The timeout is long enough for the isolate to spawn and write the first
      // marker, and far shorter than the 1500ms block that follows it.
      final result = await service.classify(
        marker.path,
        timeout: const Duration(milliseconds: 400),
        entryPoint: markerEntry,
      );

      expect(result, isNull);
      expect(marker.existsSync(), isTrue,
          reason: 'the isolate must have started before the timeout fired');

      // Wait past the point where an un-killed isolate would have finished its
      // block and overwritten the marker.
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      expect(
        marker.readAsStringSync(),
        'started',
        reason: 'a killed isolate never resumes to write the second marker',
      );
    });

    test('returns null without spawning when the model is unavailable',
        () async {
      final service = InferenceService();
      await service.initialize(
        assetLoader: (_) async => bytesOfLength(0),
        retryDelay: Duration.zero,
      );

      expect(service.isReady, isFalse);
      expect(await service.classify('/unused.jpg'), isNull);
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
