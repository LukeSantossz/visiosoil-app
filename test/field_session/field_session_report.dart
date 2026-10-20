import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/photograph_measurement.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// One photograph of a field session, as the descriptor path left it
/// (SPEC 0170). The size is the oriented frame's, and the scale and the disc
/// are null when no measurement was taken.
typedef FieldPhotograph = ({
  String name,
  int? width,
  int? height,
  ClassificationReport report,
  double? mmPerPx,
  double? discMm,
});

/// The Markdown table of [photographs] in file-name order, in the shape of
/// `docs/ml/sheet-reader-real-photographs.md`, closed by how many of them
/// were classified.
String fieldSessionReport(List<FieldPhotograph> photographs) {
  final sorted = [...photographs]..sort((a, b) => a.name.compareTo(b.name));
  final lines = [
    '| Photograph | Size | Outcome | Scale (mm/px) | Disc (mm) |',
    '|---|---|---|---|---|',
    for (final photo in sorted)
      '| ${photo.name} '
          '| ${photo.width == null ? '' : '${photo.width} × ${photo.height}'} '
          '| ${_outcome(photo.report)} '
          '| ${photo.mmPerPx?.toStringAsFixed(4) ?? ''} '
          '| ${photo.discMm?.toStringAsFixed(1) ?? ''} |',
  ];
  final classified = sorted.where((photo) => photo.report.result != null);
  return '${lines.join('\n')}\n\n'
      '${classified.length} of ${sorted.length} classified\n';
}

String _outcome(ClassificationReport report) {
  final result = report.result;
  if (result == null) return '`${report.cause!.name}`';
  return '${result.textureClass}, '
      '${(result.confidenceScore * 100).round()} %';
}

/// Runs every JPEG in [folder] through the path the app runs: the shipped
/// contract and [a4SheetMeasurer], wrapped to keep the frame it was handed and
/// the measurement it returned. Throws a [StateError] naming [folder] when it
/// holds no JPEG, rather than reporting an empty session.
Future<List<FieldPhotograph>> readFieldSession(String folder) async {
  final files =
      Directory(folder)
          .listSync()
          .whereType<File>()
          .where(
            (file) => const {
              '.jpg',
              '.jpeg',
            }.contains(p.extension(file.path).toLowerCase()),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('No JPEG photograph in $folder');
  }
  final contract = parseDescriptorContract(
    File('assets/models/spec.json').readAsStringSync(),
  ).contract!;

  return [
    for (final file in files) await _read(file, contract),
  ];
}

Future<FieldPhotograph> _read(File file, DescriptorContract contract) async {
  int? width;
  int? height;
  PhotographMeasurement? measurement;
  final report = await InferenceService.runInference(file.path, contract, (
    frame,
  ) {
    width = frame.width;
    height = frame.height;
    final measured = a4SheetMeasurer(frame);
    measurement = measured.measurement;
    return measured;
  });
  final taken = measurement;
  return (
    name: p.basename(file.path),
    width: width,
    height: height,
    report: report,
    mmPerPx: taken?.mmPerPx,
    discMm: taken == null ? null : taken.diameterPx * taken.mmPerPx,
  );
}
