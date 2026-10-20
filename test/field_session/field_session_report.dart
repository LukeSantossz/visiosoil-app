import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/descriptors/photograph_measurement.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// One photograph of a field session, as the descriptor path left it
/// (SPEC 0170). The size is the oriented frame's, and the scale and the disc
/// are null when no measurement was taken. [expected] and [sample] are the
/// class and soil sample its folder names, null for an unlabelled folder
/// (SPEC 0174).
typedef FieldPhotograph = ({
  String name,
  String? sample,
  String? expected,
  int? width,
  int? height,
  ClassificationReport report,
  double? mmPerPx,
  double? discMm,
});

/// The Markdown table of [photographs] in file-name order, in the shape of
/// `docs/ml/sheet-reader-real-photographs.md`, closed by how many of them
/// were classified. Labelled photographs add the expected class and whether
/// the read matched, then the accuracy per class in [classes], the refusals
/// by cause and the confusion matrix (SPEC 0174).
String fieldSessionReport(
  List<FieldPhotograph> photographs, {
  List<String> classes = const [],
}) {
  final sorted = [...photographs]..sort((a, b) => a.name.compareTo(b.name));
  final labelled = sorted.any((photo) => photo.expected != null);
  String size(FieldPhotograph photo) =>
      photo.width == null ? '' : '${photo.width} × ${photo.height}';
  String scale(FieldPhotograph photo) =>
      '| ${photo.mmPerPx?.toStringAsFixed(4) ?? ''} '
      '| ${photo.discMm?.toStringAsFixed(1) ?? ''} |';
  final lines = labelled
      ? [
          '| Photograph | Sample | Expected | Size | Outcome | Match '
              '| Scale (mm/px) | Disc (mm) |',
          '|---|---|---|---|---|---|---|---|',
          for (final photo in sorted)
            '| ${photo.name} | ${photo.sample ?? ''} '
                '| ${photo.expected ?? ''} | ${size(photo)} '
                '| ${_outcome(photo.report)} | ${_match(photo)} '
                '${scale(photo)}',
        ]
      : [
          '| Photograph | Size | Outcome | Scale (mm/px) | Disc (mm) |',
          '|---|---|---|---|---|',
          for (final photo in sorted)
            '| ${photo.name} | ${size(photo)} '
                '| ${_outcome(photo.report)} ${scale(photo)}',
        ];
  final classified = sorted.where((photo) => photo.report.result != null);
  final count = '${classified.length} of ${sorted.length} classified';
  if (!labelled) return '${lines.join('\n')}\n\n$count\n';
  return '${lines.join('\n')}\n\n$count\n\n'
      '${_accuracy(sorted, classes).join('\n')}\n\n'
      '${_refusals(sorted)}\n\n'
      '${_confusion(classified.toList(), classes).join('\n')}\n';
}

String _outcome(ClassificationReport report) {
  final result = report.result;
  if (result == null) return '`${report.cause!.name}`';
  return '${result.textureClass}, '
      '${(result.confidenceScore * 100).round()} %';
}

String _match(FieldPhotograph photo) {
  final read = photo.report.result?.textureClass;
  if (read == null || photo.expected == null) return '';
  return read == photo.expected ? '✓' : '✗';
}

/// One line per class: the classified photographs read right, out of those
/// classified, with the refused ones apart.
List<String> _accuracy(List<FieldPhotograph> photos, List<String> classes) => [
  for (final name in classes)
    if (photos.any((photo) => photo.expected == name))
      () {
        final ofClass = photos.where((photo) => photo.expected == name);
        final classified = ofClass.where((p) => p.report.result != null);
        final right = classified.where((p) => _match(p) == '✓');
        return '$name: ${right.length} of ${classified.length} classified '
            'right (${ofClass.length - classified.length} refused)';
      }(),
];

String _refusals(List<FieldPhotograph> photos) {
  final counts = <String, int>{};
  for (final photo in photos) {
    final cause = photo.report.cause;
    if (cause != null) counts.update(cause.name, (n) => n + 1, ifAbsent: () => 1);
  }
  final named = counts.entries.map((e) => '`${e.key}` ${e.value}').join(', ');
  return 'Refused: ${named.isEmpty ? 'none' : named}';
}

/// Rows are the expected class, columns the class read, both in [classes]'
/// order, over the classified photographs.
List<String> _confusion(List<FieldPhotograph> classified, List<String> classes) {
  int cell(String expected, String read) => classified
      .where(
        (photo) =>
            photo.expected == expected &&
            photo.report.result!.textureClass == read,
      )
      .length;
  return [
    '| Expected \\ Read | ${classes.join(' | ')} |',
    '|---|${'---|' * classes.length}',
    for (final expected in classes)
      '| $expected | '
          '${[for (final read in classes) cell(expected, read)].join(' | ')} |',
  ];
}

/// [value] rounded half to even, as `resampleToCanonical` rounds a size.
int roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final fraction = value - floor;
  final lower = floor.toInt();
  if (fraction > 0.5) return lower + 1;
  if (fraction < 0.5) return lower;
  return lower.isEven ? lower : lower + 1;
}

/// Runs every JPEG in [folder] through the path the app runs: the shipped
/// contract and [a4SheetMeasurer], wrapped to keep the frame it was handed and
/// the measurement it returned. Throws a [StateError] naming [folder] when it
/// holds no JPEG, rather than reporting an empty session.
///
/// A folder whose first level holds folders is labelled (SPEC 0174): each is
/// a contract class, and each folder inside it a soil sample. With
/// [exportDir], every measured photograph is also written there at the
/// canonical scale, with a `manifest.json` row each.
Future<List<FieldPhotograph>> readFieldSession(
  String folder, {
  String? exportDir,
}) async {
  final contract = parseDescriptorContract(
    File('assets/models/spec.json').readAsStringSync(),
  ).contract!;
  final entries = _labelledFiles(folder, contract.classes);
  if (entries.isEmpty) {
    throw StateError('No JPEG photograph in $folder');
  }

  final manifest = <Map<String, Object?>>[];
  final read = [
    for (final entry in entries)
      await _read(entry, contract, exportDir: exportDir, manifest: manifest),
  ];
  if (exportDir != null) {
    File(p.join(exportDir, 'manifest.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
  }
  return read;
}

bool _isJpeg(File file) =>
    const {'.jpg', '.jpeg'}.contains(p.extension(file.path).toLowerCase());

List<({File file, String? expected, String? sample})> _labelledFiles(
  String folder,
  List<String> classes,
) {
  List<File> jpegs(Directory directory) =>
      directory.listSync().whereType<File>().where(_isJpeg).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final root = Directory(folder);
  final classDirs = root.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (classDirs.isEmpty) {
    return [
      for (final file in jpegs(root)) (file: file, expected: null, sample: null),
    ];
  }
  return [
    for (final classDir in classDirs)
      ...() {
        final name = p.basename(classDir.path);
        if (!classes.contains(name)) {
          throw StateError(
            'The folder "$name" in $folder is not a class of the contract; '
            'the classes are ${classes.join(', ')}',
          );
        }
        final samples = classDir.listSync().whereType<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        return [
          for (final file in jpegs(classDir))
            (file: file, expected: name, sample: name),
          for (final sample in samples)
            for (final file in jpegs(sample))
              (file: file, expected: name, sample: p.basename(sample.path)),
        ];
      }(),
  ];
}

Future<FieldPhotograph> _read(
  ({File file, String? expected, String? sample}) entry,
  DescriptorContract contract, {
  String? exportDir,
  required List<Map<String, Object?>> manifest,
}) async {
  int? width;
  int? height;
  PhotographMeasurement? measurement;
  final report = await InferenceService.runInference(
    entry.file.path,
    contract,
    (frame) {
      width = frame.width;
      height = frame.height;
      final measured = a4SheetMeasurer(frame);
      measurement = measured.measurement;
      return measured;
    },
  );
  final taken = measurement;
  final name = p.basename(entry.file.path);
  if (exportDir != null && taken != null) {
    manifest.add(_export(name, entry, taken, contract, exportDir));
  }
  return (
    name: name,
    sample: entry.sample,
    expected: entry.expected,
    width: width,
    height: height,
    report: report,
    mmPerPx: taken?.mmPerPx,
    discMm: taken == null ? null : taken.diameterPx * taken.mmPerPx,
  );
}

/// Writes [measurement]'s square at the canonical scale as a PNG in
/// [exportDir] and returns its manifest row. A square coarser than the
/// canonical is upsampled and flagged, which the app itself never does.
Map<String, Object?> _export(
  String name,
  ({File file, String? expected, String? sample}) entry,
  PhotographMeasurement measurement,
  DescriptorContract contract,
  String exportDir,
) {
  final canonical = contract.canonicalMmPerPx;
  final ratio = measurement.mmPerPx / canonical;
  final frame = measurement.frame;
  final upsampled = measurement.mmPerPx > canonical;
  final RgbFrame region;
  if (upsampled) {
    region = resizeBilinear(
      frame,
      math.max(1, roundHalfEven(frame.width * ratio)),
      math.max(1, roundHalfEven(frame.height * ratio)),
    );
  } else {
    region = resampleToCanonical(
      frame,
      measuredMmPerPx: measurement.mmPerPx,
      canonicalMmPerPx: canonical,
    ).frame!;
  }
  final file = '${entry.sample ?? 'unlabelled'}_'
      '${p.basenameWithoutExtension(name)}.png';
  File(p.join(exportDir, file))
    ..createSync(recursive: true)
    ..writeAsBytesSync(
      img.encodePng(
        img.Image.fromBytes(
          width: region.width,
          height: region.height,
          bytes: region.rgb.buffer,
          numChannels: 3,
        ),
      ),
    );
  return {
    'file': file,
    'class': entry.expected,
    'sample': entry.sample,
    'source': name,
    'measured_mm_per_px': measurement.mmPerPx,
    'canonical_mm_per_px': canonical,
    'centre_y': measurement.centreYPx * ratio,
    'centre_x': measurement.centreXPx * ratio,
    'diameter': measurement.diameterPx * ratio,
    'upsampled': upsampled,
  };
}
