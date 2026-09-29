import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_descriptors.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/descriptors/photograph_measurement.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// What one classification costs on a device, phase by phase (SPEC 0086, A7).
///
/// Run on the emulator in profile mode, which is AOT-compiled as release is:
///
///     flutter drive --profile -d emulator-5554 \
///       --driver=test_driver/integration_test.dart \
///       --target=integration_test/descriptor_path_cost_test.dart
///
/// The timings land in `build/integration_response_data.json`.

/// A 12 MP photograph in portrait, as a phone's main camera takes it.
const _widthPx = 3024;
const _heightPx = 4032;

/// A 90 mm dish spanning 2 700 px: a typical measured scale at 12 MP.
const _dishMm = 90.0;
const _dishPx = 2700.0;

const _runs = 5;

/// Stands in for the A4-sheet reader, which does not exist yet. Top-level so
/// that it can be sent to the classification isolate.
({PhotographMeasurement? measurement, ClassificationFailureCause? cause})
typicalDishMeasurer(RgbFrame frame) => (
  measurement: PhotographMeasurement(
    frame: frame,
    mmPerPx: _dishMm / _dishPx,
    centreYPx: frame.height / 2.0,
    centreXPx: frame.width / 2.0,
    diameterPx: _dishPx,
  ),
  cause: null,
);

/// Uniform noise, the worst case for a JPEG decoder: nothing compresses, so a
/// real photograph at this resolution decodes no slower.
String _writeNoisePhotograph() {
  final random = math.Random(7);
  final rgb = Uint8List(_widthPx * _heightPx * 3);
  for (var i = 0; i < rgb.length; i++) {
    rgb[i] = random.nextInt(256);
  }
  final image = img.Image.fromBytes(
    width: _widthPx,
    height: _heightPx,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final file = File('${Directory.systemTemp.createTempSync().path}/noise.jpg')
    ..writeAsBytesSync(img.encodeJpg(image, quality: 90));
  return file.path;
}

int _msSince(Stopwatch clock) {
  final ms = clock.elapsedMilliseconds;
  clock.reset();
  return ms;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the_harness_times_every_phase', (tester) async {
    final path = _writeNoisePhotograph();
    final contract = parseDescriptorContract(
      await rootBundle.loadString(InferenceService.contractPath),
    ).contract!;

    final timings = <String, List<int>>{
      for (final phase in [
        'decode',
        'orientation',
        'frame',
        'grid',
        'describe',
        'score',
        'classify',
      ])
        phase: <int>[],
    };
    var patchCount = 0;

    for (var run = 0; run < _runs; run++) {
      final bytes = File(path).readAsBytesSync();
      final clock = Stopwatch()..start();

      final decoded = img.decodeImage(bytes)!;
      timings['decode']!.add(_msSince(clock));
      final baked = img.bakeOrientation(decoded);
      timings['orientation']!.add(_msSince(clock));
      final frame = InferenceService.frameOf(baked);
      timings['frame']!.add(_msSince(clock));

      final measurement = typicalDishMeasurer(frame).measurement!;
      final cut = canonicalPatches(
        measurement.frame,
        measuredMmPerPx: measurement.mmPerPx,
        centreYPx: measurement.centreYPx,
        centreXPx: measurement.centreXPx,
        diameterPx: measurement.diameterPx,
        canonicalMmPerPx: contract.canonicalMmPerPx,
        patchPx: contract.patchPx,
        strideFraction: contract.patchStrideFraction,
        minPatches: contract.minPatches,
      );
      timings['grid']!.add(_msSince(clock));
      final patches = cut.patches!;
      patchCount = patches.length;

      final features = [
        for (final patch in patches)
          describePatch(patch, contract.patchPx, contract.patchPx),
      ];
      timings['describe']!.add(_msSince(clock));
      contract.distribution(features);
      timings['score']!.add(_msSince(clock));
    }

    // End to end, as the capture screen calls it: the isolate spawn, the
    // contract copy and every phase above. The timeout is lifted so that a
    // run slower than the shipped 15 s is measured rather than cut off.
    final service = InferenceService(measurer: typicalDishMeasurer);
    expect(await service.initialize(), isNull);
    for (var run = 0; run < _runs; run++) {
      final clock = Stopwatch()..start();
      final report = await service.classify(
        path,
        timeout: const Duration(minutes: 5),
      );
      timings['classify']!.add(clock.elapsedMilliseconds);
      expect(report.outcome, ClassificationOutcome.ok);
    }

    binding.reportData = {
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      'photograph': {
        'width_px': _widthPx,
        'height_px': _heightPx,
        'jpeg_bytes': File(path).lengthSync(),
        'content': 'uniform noise, quality 90',
        'mm_per_px': _dishMm / _dishPx,
      },
      'patches': patchCount,
      'runs': _runs,
      'timings_ms': timings,
    };
  }, timeout: const Timeout(Duration(minutes: 30)));
}
