import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_descriptors.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/descriptors/photograph_measurement.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// What one classification costs on a device, phase by phase (SPEC 0086, A7),
/// and what the A4-sheet reader adds to it (SPEC 0092).
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

/// The sheet scene's scale: an A4 sheet 3 564 px long, most of the frame's
/// height, as the protocol frames it.
const _sheetPxPerMm = 12;

/// The protocol's round soil patch.
const _soilMm = 90;

const _runs = 5;

/// Stands in for a measurer on the noise scene, which has no sheet to read.
/// Top-level so that it can be sent to the classification isolate.
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

String _writeJpeg(Uint8List rgb, String name) {
  final image = img.Image.fromBytes(
    width: _widthPx,
    height: _heightPx,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final file = File('${Directory.systemTemp.createTempSync().path}/$name')
    ..writeAsBytesSync(img.encodeJpg(image, quality: 90));
  return file.path;
}

/// Uniform noise, the worst case for a JPEG decoder: nothing compresses, so a
/// real photograph at this resolution decodes no slower.
String _writeNoisePhotograph() {
  final random = math.Random(7);
  final rgb = Uint8List(_widthPx * _heightPx * 3);
  for (var i = 0; i < rgb.length; i++) {
    rgb[i] = random.nextInt(256);
  }
  return _writeJpeg(rgb, 'noise.jpg');
}

/// A sheet laid square in the middle of the frame, on a grey surface, with the
/// protocol's soil patch in its middle. It is drawn to cost what a photograph
/// taken to the protocol costs; the reader's geometry is graded elsewhere,
/// against SPEC 0091's scenes.
String _writeSheetPhotograph() {
  final random = math.Random(92);
  final sheetWidth = sheetWidthMm.round() * _sheetPxPerMm;
  final sheetHeight = sheetHeightMm.round() * _sheetPxPerMm;
  final left = (_widthPx - sheetWidth) ~/ 2;
  final top = (_heightPx - sheetHeight) ~/ 2;
  final centreX = left + sheetWidth / 2, centreY = top + sheetHeight / 2;
  final radius = _soilMm / 2 * _sheetPxPerMm;

  final rgb = Uint8List(_widthPx * _heightPx * 3);
  for (var y = 0; y < _heightPx; y++) {
    for (var x = 0; x < _widthPx; x++) {
      final dx = x + 0.5 - centreX, dy = y + 0.5 - centreY;
      final onSheet =
          x >= left &&
          x < left + sheetWidth &&
          y >= top &&
          y < top + sheetHeight;
      final (base, spread) = dx * dx + dy * dy <= radius * radius
          ? (const [112, 82, 58], 40)
          : onSheet
          ? (const [240, 238, 232], 4)
          : (const [126, 126, 124], 12);
      final shade = random.nextInt(2 * spread + 1) - spread;
      final i = (y * _widthPx + x) * 3;
      for (var k = 0; k < 3; k++) {
        rgb[i + k] = (base[k] + shade).clamp(0, 255);
      }
    }
  }
  return _writeJpeg(rgb, 'sheet.jpg');
}

int _msSince(Stopwatch clock) {
  final ms = clock.elapsedMilliseconds;
  clock.reset();
  return ms;
}

/// Times every phase on this thread, then `classify` end to end, as the
/// capture screen calls it: the isolate spawn, the contract copy and every
/// phase. The timeout is lifted so that a run slower than the shipped 15 s is
/// measured rather than cut off.
Future<Map<String, Object>> _timeScene(
  String path,
  DescriptorContract contract,
  PhotographMeasurer measurer,
  InferenceService service,
) async {
  final timings = <String, List<int>>{
    for (final phase in [
      'decode',
      'orientation',
      'frame',
      'measure',
      'grid',
      'describe',
      'score',
      'classify',
    ])
      phase: <int>[],
  };
  var patchCount = 0;
  var mmPerPx = 0.0;

  for (var run = 0; run < _runs; run++) {
    final bytes = File(path).readAsBytesSync();
    final clock = Stopwatch()..start();

    final decoded = img.decodeImage(bytes)!;
    timings['decode']!.add(_msSince(clock));
    final baked = img.bakeOrientation(decoded);
    timings['orientation']!.add(_msSince(clock));
    final frame = InferenceService.frameOf(baked);
    timings['frame']!.add(_msSince(clock));

    final measurement = measurer(frame).measurement!;
    timings['measure']!.add(_msSince(clock));
    mmPerPx = measurement.mmPerPx;
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

  expect(await service.initialize(), isNull);
  for (var run = 0; run < _runs; run++) {
    final clock = Stopwatch()..start();
    final report = await service.classify(
      path,
      timeout: const Duration(minutes: 5),
    );
    timings['classify']!.add(clock.elapsedMilliseconds);
    expect(report.outcome, ClassificationOutcome.ok, reason: '${report.cause}');
  }

  return {
    'jpeg_bytes': File(path).lengthSync(),
    'mm_per_px': mmPerPx,
    'patches': patchCount,
    'timings_ms': timings,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the_harness_times_every_phase', (tester) async {
    final contract = parseDescriptorContract(
      await rootBundle.loadString(InferenceService.contractPath),
    ).contract!;

    final noise = await _timeScene(
      _writeNoisePhotograph(),
      contract,
      typicalDishMeasurer,
      InferenceService(measurer: typicalDishMeasurer),
    );
    // The service as the app builds it, with the A4-sheet reader.
    final sheet = await _timeScene(
      _writeSheetPhotograph(),
      contract,
      a4SheetMeasurer,
      InferenceService(),
    );

    binding.reportData = {
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      'width_px': _widthPx,
      'height_px': _heightPx,
      'runs': _runs,
      'scenes': {
        'noise': {
          'content': 'uniform noise, quality 90, a typical dish measured',
          ...noise,
        },
        'sheet': {
          'content':
              'an A4 sheet at $_sheetPxPerMm px/mm with a $_soilMm mm soil '
              'patch, quality 90, measured by the A4-sheet reader',
          ...sheet,
        },
      },
    };
  }, timeout: const Timeout(Duration(minutes: 30)));
}
