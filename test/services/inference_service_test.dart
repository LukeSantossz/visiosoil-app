// Acceptance criteria for SPEC 0083, the descriptor path wired into
// `InferenceService`, and for the SPEC 0078 criteria it keeps: `classify`
// reports an outcome and a named cause, never null. Each test named after a
// criterion carries its name exactly;
// `docs/specs/0083-wire-the-descriptor-path-into-the-inference-service.md`.
// SPEC 0092 adds the A4-sheet reader as the default measurer.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_descriptors.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/descriptors/photograph_measurement.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/models/class_score.dart';

const _shippedContract = 'assets/models/spec.json';

/// The side of the synthetic photographs: enough soil at the canonical scale
/// for a 3 x 3 grid of 160 px patches, which needs a disc of about 453 px.
const _side = 520;

// Isolate entry points and the measurers sent to them must be top-level: a
// closure capturing test state is not sendable to a spawned isolate.

const _result = InferenceResult(textureClass: 'Media', confidenceScore: 0.75);

/// Responds immediately with a report, standing in for a successful run.
void respondingEntry(InferenceRequest request) {
  request.responsePort.send(const ClassificationReport.ok(_result));
}

/// Keeps the isolate alive without ever responding, so the timeout fires with
/// a live isolate to kill.
void hangingEntry(InferenceRequest request) {
  ReceivePort(); // an open port keeps this isolate from terminating
}

/// Dies before answering, as a worker that hits an uncaught error does.
void throwingEntry(InferenceRequest request) {
  throw StateError('the worker died before answering');
}

/// Writes a marker, blocks, then overwrites it: if the second write never
/// lands, the isolate was killed rather than merely abandoned.
void markerEntry(InferenceRequest request) {
  final marker = File(request.imagePath);
  marker.writeAsStringSync('started');
  sleep(const Duration(milliseconds: 1500));
  marker.writeAsStringSync('started+finished');
}

/// The shipped contract's canonical scale, read the way the service reads it.
double _canonical() =>
    (jsonDecode(
              File(_shippedContract).readAsStringSync(),
            )['geometry']['canonical_mm_per_px']
            as num)
        .toDouble();

/// A measurer that finds the soil filling the frame, at the canonical scale.
({PhotographMeasurement? measurement, ClassificationFailureCause? cause})
wholeFrameMeasurer(RgbFrame frame) => (
  measurement: PhotographMeasurement(
    frame: frame,
    mmPerPx: _canonical(),
    centreYPx: frame.height / 2.0,
    centreXPx: frame.width / 2.0,
    diameterPx: math.min(frame.width, frame.height).toDouble(),
  ),
  cause: null,
);

/// Seeded noise, the same bytes on every run and every host.
Uint8List _noise(int width, int height, int seed) {
  final random = math.Random(seed);
  return Uint8List.fromList(
    List<int>.generate(width * height * 3, (_) => random.nextInt(256)),
  );
}

void main() {
  late DescriptorContract contract;

  setUpAll(() {
    contract = parseDescriptorContract(
      File(_shippedContract).readAsStringSync(),
    ).contract!;
  });

  Directory tempDir(String name) {
    final dir = Directory.systemTemp.createTempSync(name);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  Future<String> shippedLoader(String key) => File(key).readAsString();

  Future<InferenceService> readyService() async {
    final service = InferenceService();
    expect(
      await service.initialize(
        assetLoader: shippedLoader,
        retryDelay: Duration.zero,
      ),
      isNull,
    );
    return service;
  }

  /// A lossless photograph of [rgb] on disk, so the decoded frame is [rgb].
  String writePng(Uint8List rgb, int width, int height, String name) {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      numChannels: 3,
    );
    return (File(
      p.join(tempDir(name).path, 'soil.png'),
    )..writeAsBytesSync(img.encodePng(image))).path;
  }

  group('InferenceService.initialize', () {
    test('the_shipped_contract_loads', () async {
      final service = await readyService();
      expect(service.isReady, isTrue);
    });

    test('retries transient failures then succeeds', () async {
      var calls = 0;
      final service = InferenceService();
      final cause = await service.initialize(
        retryDelay: Duration.zero,
        assetLoader: (key) async {
          calls++;
          if (calls < 3) throw Exception('transient');
          return shippedLoader(key);
        },
      );
      expect(cause, isNull);
      expect(calls, 3);
    });

    test('missing_contract_asset_yields_contract_missing', () async {
      var calls = 0;
      Future<String> loader(String _) async {
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

      expect(first, ClassificationFailureCause.contractMissing);
      expect(second, ClassificationFailureCause.contractMissing);
      expect(callsAfterFirst, 3); // bounded attempts per call
      expect(calls, greaterThan(callsAfterFirst)); // a later call may retry
    });

    test('malformed_contract_yields_contract_malformed', () async {
      var calls = 0;
      final service = InferenceService();
      Future<String> loader(String _) async {
        calls++;
        return '{ not json';
      }

      final first = await service.initialize(
        assetLoader: loader,
        retryDelay: Duration.zero,
      );
      final second = await service.initialize(
        assetLoader: loader,
        retryDelay: Duration.zero,
      );

      expect(first, ClassificationFailureCause.contractMalformed);
      expect(second, ClassificationFailureCause.contractMalformed);
      expect(calls, 1); // a build fact: not reloaded

      // `classify` reports the same cause, without spawning a worker.
      final report = await service.classify(
        '/unused.jpg',
        entryPoint: respondingEntry,
      );
      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.contractMalformed);
      expect(report.result, isNull);
    });

    test('unsupported_contract_yields_contract_unsupported', () async {
      var calls = 0;
      final document =
          jsonDecode(File(_shippedContract).readAsStringSync())
                as Map<String, dynamic>
            ..['spec_version'] = 3;
      final service = InferenceService();
      Future<String> loader(String _) async {
        calls++;
        return jsonEncode(document);
      }

      expect(
        await service.initialize(
          assetLoader: loader,
          retryDelay: Duration.zero,
        ),
        ClassificationFailureCause.contractUnsupported,
      );
      expect(
        await service.initialize(
          assetLoader: loader,
          retryDelay: Duration.zero,
        ),
        ClassificationFailureCause.contractUnsupported,
      );
      expect(calls, 1);
    });
  });

  group('InferenceService.classify', () {
    test('a_measured_photograph_is_classified_with_the_contract', () async {
      final rgb = _noise(_side, _side, 1);
      final path = writePng(rgb, _side, _side, 'visiosoil_measured');
      final service = InferenceService(measurer: wholeFrameMeasurer);
      await service.initialize(
        assetLoader: shippedLoader,
        retryDelay: Duration.zero,
      );

      // Through the isolate, with the measurer sent to it.
      final report = await service.classify(
        path,
        timeout: const Duration(seconds: 60),
      );
      expect(
        report.outcome,
        ClassificationOutcome.ok,
        reason: '${report.cause}',
      );

      // What the parts give for the same frame, composed by hand.
      final frame = RgbFrame(_side, _side, rgb);
      final measured = wholeFrameMeasurer(frame).measurement!;
      final patches = canonicalPatches(
        measured.frame,
        measuredMmPerPx: measured.mmPerPx,
        centreYPx: measured.centreYPx,
        centreXPx: measured.centreXPx,
        diameterPx: measured.diameterPx,
        canonicalMmPerPx: contract.canonicalMmPerPx,
        patchPx: contract.patchPx,
        strideFraction: contract.patchStrideFraction,
        minPatches: contract.minPatches,
      ).patches!;
      final expected = contract.distribution([
        for (final patch in patches)
          describePatch(patch, contract.patchPx, contract.patchPx),
      ]);

      final distribution = report.result!.distribution;
      expect(
        distribution.map((score) => score.label).toSet(),
        contract.classes.toSet(),
      );
      for (final score in distribution) {
        expect(
          score.probability,
          expected[contract.classes.indexOf(score.label)],
          reason: score.label,
        );
      }
      final probabilities = [
        for (final score in distribution) score.probability,
      ];
      expect(probabilities, [...probabilities]..sort((a, b) => b.compareTo(a)));
      expect(report.result!.textureClass, distribution.first.label);
      expect(report.result!.confidenceScore, distribution.first.probability);
    });

    test('the_default_measurer_is_the_a4_sheet_reader', () {
      expect(InferenceService().measurer, a4SheetMeasurer);
    });

    test(
      'a_sheet_photograph_is_classified',
      () async {
        // SPEC 0091's frontal scene enlarged to 12 MP, the size a phone
        // camera writes, so the sheet is read finer than the canonical scale.
        final scene = img.decodeJpg(
          File('test/fixtures/sheet/sheet_frontal.jpg').readAsBytesSync(),
        )!;
        final photograph = img.copyResize(
          scene,
          width: 3000,
          height: 4000,
          interpolation: img.Interpolation.linear,
        );
        final path = (File(
          p.join(tempDir('visiosoil_sheet').path, 'sheet.jpg'),
        )..writeAsBytesSync(img.encodeJpg(photograph, quality: 90))).path;

        // The default measurer, through the isolate. The timeout is widened
        // because a test VM is not the device; the harness measures cost.
        final service = await readyService();
        final report = await service.classify(
          path,
          timeout: const Duration(seconds: 120),
        );
        expect(
          report.outcome,
          ClassificationOutcome.ok,
          reason: '${report.cause}',
        );
        expect(contract.classes, contains(report.result!.textureClass));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

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

      final report = await service.classify(
        marker.path,
        timeout: const Duration(milliseconds: 400),
        entryPoint: markerEntry,
      );

      expect(report.cause, ClassificationFailureCause.timeout);
      expect(
        marker.existsSync(),
        isTrue,
        reason: 'the isolate must have started before the timeout fired',
      );
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
      expect(
        clock.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'a dead worker is reported at once, not at the timeout',
      );
    });
  });

  group('InferenceService.runInference', () {
    Future<ClassificationReport> run(
      String path,
      PhotographMeasurer measurer,
    ) => InferenceService.runInference(path, contract, measurer);

    test('missing_image_file_yields_image_missing', () async {
      final missing = p.join(tempDir('visiosoil_missing').path, 'absent.jpg');

      final report = await run(missing, wholeFrameMeasurer);

      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.imageMissing);
    });

    test('undecodable_image_yields_image_undecodable', () async {
      final file = File(
        p.join(tempDir('visiosoil_garbage').path, 'noise.jpg'),
      )..writeAsBytesSync(List<int>.generate(512, (index) => index * 37 % 251));

      final report = await run(file.path, wholeFrameMeasurer);

      expect(report.cause, ClassificationFailureCause.imageUndecodable);
    });

    test('patch_refusals_yield_their_causes', () async {
      final path = writePng(
        _noise(_side, _side, 3),
        _side,
        _side,
        'visiosoil_refused',
      );

      PhotographMeasurer measuring({
        double scale = 1.0,
        double? centreY,
        double diameter = _side * 1.0,
      }) =>
          (frame) => (
            measurement: PhotographMeasurement(
              frame: frame,
              mmPerPx: _canonical() * scale,
              centreYPx: centreY ?? frame.height / 2.0,
              centreXPx: frame.width / 2.0,
              diameterPx: diameter,
            ),
            cause: null,
          );

      expect(
        (await run(path, measuring(scale: 1.1))).cause,
        ClassificationFailureCause.photographTooCoarse,
      );
      expect(
        (await run(path, measuring(diameter: 200))).cause,
        ClassificationFailureCause.soilRegionTooSmall,
      );
      expect(
        (await run(path, measuring(centreY: 120))).cause,
        ClassificationFailureCause.soilRegionOutsideFrame,
      );
    });

    test('orientation_is_baked_before_measuring', () async {
      // Stored 60 wide and 40 tall, tagged to be displayed rotated a quarter
      // turn, so the displayed frame is 40 wide and 60 tall.
      final image = img.Image(width: 60, height: 40);
      image.exif.imageIfd.orientation = 6;
      final path = (File(
        p.join(tempDir('visiosoil_exif').path, 'soil.jpg'),
      )..writeAsBytesSync(img.encodeJpg(image))).path;

      final seen = <(int, int)>[];
      await run(path, (frame) {
        seen.add((frame.width, frame.height));
        return (
          measurement: null,
          cause: ClassificationFailureCause.sheetNotFound,
        );
      });

      expect(seen, [(40, 60)]);
    });

    test('a_throw_in_the_pipeline_yields_computation_error', () async {
      final path = writePng(_noise(32, 32, 4), 32, 32, 'visiosoil_throw');

      final report = await run(
        path,
        (frame) => throw StateError('the measurer failed'),
      );

      expect(report.outcome, ClassificationOutcome.failed);
      expect(report.cause, ClassificationFailureCause.computationError);
    });
  });

  group('InferenceService.buildDistribution', () {
    test('non_probability_output_yields_output_invalid', () {
      for (final probabilities in [
        [double.nan, 0.2, 0.3, 0.4],
        [1.1, 0.0, 0.0, 0.0],
        [-0.1, 0.4, 0.4, 0.3],
      ]) {
        expect(
          InferenceService.buildDistribution(probabilities, contract.classes),
          isNull,
          reason: '$probabilities',
        );
        final report = InferenceService.reportFor(
          probabilities,
          contract.classes,
        );
        expect(
          report.cause,
          ClassificationFailureCause.outputInvalid,
          reason: '$probabilities',
        );
      }
    });
  });

  // SPEC 0097: what a record needs to keep, carried on the result.
  group('InferenceService.reportFor provenance', () {
    test('the_report_names_the_contract_versions', () async {
      final report = InferenceService.reportFor(
        [0.1, 0.6, 0.1, 0.2],
        contract.classes,
        modelVersion: contract.modelVersion,
        datasetVersion: contract.datasetVersion,
      );
      final result = report.result!;
      expect(result.modelVersion, contract.modelVersion);
      expect(result.datasetVersion, contract.datasetVersion);
      expect(result.classes, contract.classes);
      // The same scores, in the contract's order rather than by probability.
      expect(
        result.classDistribution!.map((score) => score.label),
        contract.classes,
      );
      expect(
        result.classDistribution!.map((score) => score.probability),
        [0.1, 0.6, 0.1, 0.2],
      );

      // And through the isolate, from the shipped contract.
      final path = writePng(_noise(_side, _side, 6), _side, _side, 'visiosoil_versions');
      final service = InferenceService(measurer: wholeFrameMeasurer);
      await service.initialize(
        assetLoader: shippedLoader,
        retryDelay: Duration.zero,
      );
      final classified = await service.classify(
        path,
        timeout: const Duration(seconds: 60),
      );
      expect(classified.outcome, ClassificationOutcome.ok);
      expect(classified.result!.modelVersion, contract.modelVersion);
      expect(classified.result!.datasetVersion, contract.datasetVersion);
      expect(classified.result!.classes, contract.classes);
    });

    test('a_result_without_a_class_order_has_no_class_distribution', () {
      const result = InferenceResult(textureClass: 'Media', confidenceScore: 0.6);
      expect(result.classDistribution, isNull);

      // A distribution that misses a class of the order is not stored in part.
      const partial = InferenceResult(
        textureClass: 'Media',
        confidenceScore: 0.6,
        distribution: [ClassScore(label: 'Media', probability: 0.6)],
        classes: ['Arenosa', 'Media'],
      );
      expect(partial.classDistribution, isNull);
    });
  });

  test('failure_causes_follow_adr_0015', () {
    final lines = File(
      'docs/adr/0015-classification-reports-a-named-failure-cause.md',
    ).readAsLinesSync();
    // The current table is the first one after the latest "Amended" heading;
    // the table under Decided is kept as it was approved.
    final amended = lines.lastIndexWhere(
      (line) => line.startsWith('### Amended'),
    );
    expect(amended, isNot(-1), reason: 'ADR 0015 carries no amendment');
    final table = lines
        .skip(amended)
        .skipWhile((line) => !line.trimLeft().startsWith('|'))
        .takeWhile((line) => line.trimLeft().startsWith('|'))
        .where((line) => line.contains('`'))
        .join('\n');
    final named = RegExp(
      r'`(\w+)`',
    ).allMatches(table).map((match) => match.group(1)!).toSet();

    expect(ClassificationFailureCause.values, hasLength(14));
    expect(
      ClassificationFailureCause.values.map((cause) => cause.name).toSet(),
      named,
    );
    expect(ClassificationOutcome.values.map((outcome) => outcome.name), [
      'ok',
      'rejectedOod',
      'failed',
    ]);
  });
}
