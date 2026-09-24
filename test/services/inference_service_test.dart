// Acceptance criteria for SPEC 0078: `classify` reports an outcome and a named
// cause, never null. Each test named after a criterion carries its name
// exactly; `docs/specs/0078-classify-reports-an-outcome-and-a-named-cause.md`.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart' show TensorType;
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

// Isolate entry points must be top-level (or static) so they can be sent to a
// spawned isolate; a closure capturing test state is not sendable.

const _result = InferenceResult(textureClass: 'Media', confidenceScore: 0.75);

/// Responds immediately with a report, standing in for a successful run.
void respondingEntry(InferenceRequest request) {
  request.responsePort.send(const ClassificationReport.ok(_result));
}

/// Keeps the isolate alive without ever responding, so the timeout fires with
/// a live isolate to kill — an entry point that simply returns would let the
/// isolate exit on its own and prove nothing.
void hangingEntry(InferenceRequest request) {
  ReceivePort(); // an open port keeps this isolate from terminating
}

/// Dies before answering, as a worker that hits an uncaught error does.
void throwingEntry(InferenceRequest request) {
  throw StateError('the worker died before answering');
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

  Directory tempDir(String name) {
    final dir = Directory.systemTemp.createTempSync(name);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  Future<InferenceService> readyService() async {
    final service = InferenceService();
    await service.initialize(
      assetLoader: (_) async => bytesOfLength(8),
      retryDelay: Duration.zero,
    );
    return service;
  }

  group('InferenceService.initialize', () {
    test('returns null once the loader succeeds', () async {
      final service = InferenceService();
      final cause = await service.initialize(
        assetLoader: (_) async => bytesOfLength(8),
        retryDelay: Duration.zero,
      );
      expect(cause, isNull);
      expect(service.isReady, isTrue);
    });

    test('retries transient failures then succeeds', () async {
      var calls = 0;
      final service = InferenceService();
      final cause = await service.initialize(
        retryDelay: Duration.zero,
        assetLoader: (_) async {
          calls++;
          if (calls < 3) throw Exception('transient');
          return bytesOfLength(8);
        },
      );
      expect(cause, isNull);
      expect(calls, 3);
    });

    test('missing_model_asset_yields_model_missing', () async {
      var calls = 0;
      Future<ByteData> loader(String _) async {
        calls++;
        throw FlutterError('Unable to load asset');
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

      expect(first, ClassificationFailureCause.modelMissing);
      expect(second, ClassificationFailureCause.modelMissing);
      expect(callsAfterFirst, 3); // bounded attempts per call
      expect(calls, greaterThan(callsAfterFirst)); // a later call may retry
    });

    test('empty_model_asset_yields_model_empty', () async {
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

      expect(first, ClassificationFailureCause.modelEmpty);
      expect(second, ClassificationFailureCause.modelEmpty);
      expect(calls, 1); // an empty model is permanent: not reloaded
    });

    test('failed_initialize_returns_the_cause', () async {
      final service = InferenceService();
      final cause = await service.initialize(
        assetLoader: (_) async => bytesOfLength(0),
        retryDelay: Duration.zero,
      );
      expect(cause, ClassificationFailureCause.modelEmpty);
      expect(service.isReady, isFalse);

      // `classify` reports the same cause, without spawning a worker.
      final report = await service.classify(
        '/unused.jpg',
        entryPoint: respondingEntry,
      );
      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.modelEmpty);
      expect(report.result, isNull);

      final ready = await readyService();
      expect(
        await ready.initialize(assetLoader: (_) async => bytesOfLength(8)),
        isNull,
      );
    });
  });

  group('InferenceService.classify', () {
    test('successful_run_yields_ok_with_the_distribution', () async {
      final service = await readyService();

      final report = await service.classify(
        '/unused.jpg',
        entryPoint: respondingEntry,
      );

      expect(report.outcome, ClassificationOutcome.ok);
      expect(report.cause, isNull);
      expect(report.result!.textureClass, 'Media');
      expect(report.result!.confidenceScore, 0.75);

      // The worker's own output step: the distribution and its tie-breaking
      // are `buildDistribution`'s, unchanged.
      const probabilities = [0.3, 0.3, 0.1, 0.3];
      final interpreted = InferenceService.interpretOutput(probabilities);
      expect(interpreted.outcome, ClassificationOutcome.ok);
      expect(
        interpreted.result!.distribution,
        InferenceService.buildDistribution(probabilities, 4),
      );
      expect(
        interpreted.result!.textureClass,
        interpreted.result!.distribution.first.label,
      );
    });

    test('inference_timeout_yields_timeout', () async {
      final service = await readyService();

      final report = await service.classify(
        '/unused.jpg',
        timeout: const Duration(milliseconds: 100),
        entryPoint: hangingEntry,
      );

      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.timeout);
    });

    test('kills the isolate on timeout so it stops working', () async {
      final marker = File(p.join(tempDir('visiosoil_kill').path, 'marker.txt'));
      final service = await readyService();

      // The timeout is long enough for the isolate to spawn and write the first
      // marker, and far shorter than the 1500ms block that follows it.
      final report = await service.classify(
        marker.path,
        timeout: const Duration(milliseconds: 400),
        entryPoint: markerEntry,
      );

      expect(report.cause, ClassificationFailureCause.timeout);
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

    test('isolate_spawn_failure_yields_isolate_failure', () async {
      final service = await readyService();
      // A closure capturing a ReceivePort cannot be sent to another isolate, so
      // the spawn itself throws.
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);

      final report = await service.classify(
        '/unused.jpg',
        entryPoint: (request) => unsendable.sendPort.send(request.imagePath),
      );

      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.isolateFailure);
    });

    test('isolate_death_yields_isolate_failure', () async {
      final service = await readyService();
      final clock = Stopwatch()..start();

      final report = await service.classify(
        '/unused.jpg',
        timeout: const Duration(seconds: 10),
        entryPoint: throwingEntry,
      );

      expect(report.cause, ClassificationFailureCause.isolateFailure);
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'a dead worker is reported at once, not at the timeout');
    });
  });

  group('InferenceService.runInference', () {
    final modelBytes = Uint8List.fromList(List<int>.filled(64, 7));

    test('missing_image_file_yields_image_missing', () async {
      final missing = p.join(tempDir('visiosoil_missing').path, 'absent.jpg');

      final report = await InferenceService.runInference(missing, modelBytes);

      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.imageMissing);
    });

    test('undecodable_image_yields_image_undecodable', () async {
      final file = File(p.join(tempDir('visiosoil_garbage').path, 'noise.jpg'))
        ..writeAsBytesSync(List<int>.generate(512, (index) => index * 37 % 251));

      final report = await InferenceService.runInference(file.path, modelBytes);

      expect(report.cause, ClassificationFailureCause.imageUndecodable);
    });

    test('interpreter_error_yields_interpreter_error', () async {
      final file = File(p.join(tempDir('visiosoil_png').path, 'soil.png'))
        ..writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 16)));

      // Bytes that are not a TFLite flatbuffer: the interpreter refuses them
      // whether or not the native library loads on the test host.
      final report = await InferenceService.runInference(file.path, modelBytes);

      expect(report.cause, ClassificationFailureCause.interpreterError);
    });
  });

  group('InferenceService.checkTensors', () {
    ClassificationFailureCause? check({
      List<int> inputShape = const [1, 224, 224, 3],
      TensorType inputType = TensorType.float32,
      List<int> outputShape = const [1, 4],
      TensorType outputType = TensorType.float32,
    }) =>
        InferenceService.checkTensors(
          inputShape: inputShape,
          inputType: inputType,
          outputShape: outputShape,
          outputType: outputType,
        );

    test(
        'interpreter_disagreeing_with_the_app_yields_model_contract_mismatch',
        () {
      expect(check(), isNull);

      const mismatch = ClassificationFailureCause.modelContractMismatch;
      expect(check(inputShape: const [1, 160, 160, 3]), mismatch);
      expect(check(inputShape: const [1, 224, 224, 1]), mismatch);
      expect(check(inputType: TensorType.uint8), mismatch);
      expect(check(outputType: TensorType.uint8), mismatch);
      expect(check(outputShape: const [1, 5]), mismatch);
    });
  });

  group('InferenceService.interpretOutput', () {
    test('non_probability_output_yields_output_invalid', () {
      for (final probabilities in [
        [double.nan, 0.2, 0.3, 0.4],
        [1.1, 0.0, 0.0, 0.0],
        [-0.1, 0.4, 0.4, 0.3],
      ]) {
        final report = InferenceService.interpretOutput(probabilities);
        expect(report.outcome, ClassificationOutcome.failed);
        expect(report.cause, ClassificationFailureCause.outputInvalid,
            reason: '$probabilities');
      }
    });

    test('a tensor of the wrong length is a mismatch, not an invalid output',
        () {
      final report = InferenceService.interpretOutput([0.2, 0.3, 0.5]);
      expect(report.cause, ClassificationFailureCause.modelContractMismatch);
    });
  });

  test('failure_causes_follow_adr_0015', () {
    final adr = File(
      'docs/adr/0015-classification-reports-a-named-failure-cause.md',
    ).readAsStringSync();
    // The causes are the backticked names in the table's rows.
    final tableRows = adr
        .split('\n')
        .where((line) => line.trimLeft().startsWith('|') && line.contains('`'))
        .join('\n');
    final named = RegExp(r'`(\w+)`')
        .allMatches(tableRows)
        .map((match) => match.group(1)!)
        .toSet();

    expect(ClassificationFailureCause.values, hasLength(12));
    expect(
      ClassificationFailureCause.values.map((cause) => cause.name).toSet(),
      named,
    );
    expect(
      ClassificationOutcome.values.map((outcome) => outcome.name),
      ['ok', 'rejectedOod', 'failed'],
    );
  });
}
