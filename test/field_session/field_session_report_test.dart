import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

import 'field_session_report.dart';

/// The table a field session is recorded with (SPEC 0170).
FieldPhotograph _classified(String name, String textureClass, double share) =>
    (
      name: name,
      sample: null,
      expected: null,
      width: 4080,
      height: 1836,
      report: ClassificationReport.ok(
        InferenceResult(textureClass: textureClass, confidenceScore: share),
      ),
      mmPerPx: 0.1292,
      discMm: 78.94,
    );

FieldPhotograph _refused(
  String name,
  ClassificationFailureCause cause, {
  double? mmPerPx,
  double? discMm,
}) => (
  name: name,
  sample: null,
  expected: null,
  width: 1836,
  height: 4080,
  report: ClassificationReport.failed(cause),
  mmPerPx: mmPerPx,
  discMm: discMm,
);

List<String> _rows(String report) =>
    report.split('\n').where((line) => line.startsWith('| IMG')).toList();

void main() {
  test('lists_each_photograph_in_name_order', () {
    final report = fieldSessionReport([
      _refused('IMG_b.jpg', ClassificationFailureCause.sheetNotFound),
      _classified('IMG_a.jpg', 'Argilosa', 0.9),
      _refused('IMG_c.jpg', ClassificationFailureCause.sheetCropped),
    ]);

    expect(
      _rows(report).map((row) => row.split('|')[1].trim()),
      ['IMG_a.jpg', 'IMG_b.jpg', 'IMG_c.jpg'],
    );
  });

  test('a_classified_photograph_shows_its_class_and_confidence', () {
    final row = _rows(
      fieldSessionReport([_classified('IMG_a.jpg', 'Muito Argilosa', 0.596)]),
    ).single;

    expect(row, contains('Muito Argilosa, 60 %'));
  });

  test('a_refused_photograph_shows_its_cause', () {
    final row = _rows(
      fieldSessionReport([
        _refused('IMG_a.jpg', ClassificationFailureCause.soilRegionTooSmall),
      ]),
    ).single;

    expect(row, contains('`soilRegionTooSmall`'));
  });

  test('the_sheet_found_shows_scale_and_disc', () {
    final rows = _rows(
      fieldSessionReport([
        _refused(
          'IMG_a.jpg',
          ClassificationFailureCause.photographTooCoarse,
          mmPerPx: 0.14337,
          discMm: 83.66,
        ),
        _refused('IMG_b.jpg', ClassificationFailureCause.sheetNotFound),
      ]),
    );

    expect(
      rows.first.split('|').map((cell) => cell.trim()).toList(),
      ['', 'IMG_a.jpg', '1836 × 4080', '`photographTooCoarse`', '0.1434', '83.7', ''],
    );
    expect(
      rows.last.split('|').map((cell) => cell.trim()).toList(),
      ['', 'IMG_b.jpg', '1836 × 4080', '`sheetNotFound`', '', '', ''],
    );
  });

  test('the_count_closes_the_report', () {
    final report = fieldSessionReport([
      _classified('IMG_a.jpg', 'Argilosa', 0.9),
      _refused('IMG_b.jpg', ClassificationFailureCause.photographTooCoarse),
      _classified('IMG_c.jpg', 'Arenosa', 0.7),
    ]);

    expect(report.trim().split('\n').last, '2 of 3 classified');
  });

  test('an_empty_folder_is_named', () async {
    final empty = Directory.systemTemp.createTempSync('field_session_');
    addTearDown(() => empty.deleteSync(recursive: true));
    File('${empty.path}/notes.txt').writeAsStringSync('no photograph here');

    await expectLater(
      readFieldSession(empty.path),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains(empty.path)),
      ),
    );
  });

  test('runs_the_committed_photographs', () async {
    final photographs = await readFieldSession('test/fixtures/sheet_photos');

    expect(photographs.map((photo) => photo.name).toList()..sort(), [
      'photo_160609.jpg',
      'photo_160645.jpg',
      'photo_160706.jpg',
      'photo_160808.jpg',
      'photo_160812.jpg',
      'photo_160903.jpg',
    ]);
    expect(
      fieldSessionReport(photographs).trim().split('\n').last,
      endsWith('of 6 classified'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  // Labelled photographs (SPEC 0174).
  const classes = ['Arenosa', 'Media', 'Muito Argilosa', 'Argilosa'];

  FieldPhotograph labelled(
    String name,
    String expected, {
    String? read,
    ClassificationFailureCause? cause,
  }) => (
    name: name,
    sample: 'S1',
    expected: expected,
    width: 100,
    height: 100,
    report: read == null
        ? ClassificationReport.failed(cause!)
        : ClassificationReport.ok(
            InferenceResult(textureClass: read, confidenceScore: 0.8),
          ),
    mmPerPx: null,
    discMm: null,
  );

  const sheetFixtures = 'test/fixtures/sheet';

  Directory tree(Map<String, String> files) {
    final root = Directory.systemTemp.createTempSync('field_labels_');
    addTearDown(() => root.deleteSync(recursive: true));
    files.forEach((path, fixture) {
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsBytesSync(File('$sheetFixtures/$fixture').readAsBytesSync());
    });
    return root;
  }

  test('labels_come_from_the_folders', () async {
    final root = tree({
      'Media/S3/a.jpg': 'sheet_cropped.jpg',
      'Arenosa/b.jpg': 'sheet_cropped.jpg',
    });

    final read = {
      for (final photo in await readFieldSession(root.path)) photo.name: photo,
    };

    expect(read['a.jpg']!.expected, 'Media');
    expect(read['a.jpg']!.sample, 'S3');
    expect(read['b.jpg']!.expected, 'Arenosa');
    expect(read['b.jpg']!.sample, 'Arenosa');
  });

  test('an_unknown_class_folder_is_named', () async {
    final root = tree({'Siltosa/a.jpg': 'sheet_cropped.jpg'});

    await expectLater(
      readFieldSession(root.path),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('Siltosa'), contains('Muito Argilosa')),
        ),
      ),
    );
  });

  test('a_labelled_row_shows_expected_and_match', () {
    final rows = fieldSessionReport([
      labelled('IMG_a.jpg', 'Media', read: 'Media'),
      labelled('IMG_b.jpg', 'Media', read: 'Argilosa'),
      labelled(
        'IMG_c.jpg',
        'Media',
        cause: ClassificationFailureCause.photographTooCoarse,
      ),
    ], classes: classes).split('\n').where((l) => l.startsWith('| IMG'));

    List<String> cells(String row) =>
        row.split('|').map((cell) => cell.trim()).toList();
    expect(cells(rows.elementAt(0)).sublist(1, 7), [
      'IMG_a.jpg',
      'S1',
      'Media',
      '100 × 100',
      'Media, 80 %',
      '✓',
    ]);
    expect(cells(rows.elementAt(1))[6], '✗');
    expect(cells(rows.elementAt(2))[3], 'Media');
    expect(cells(rows.elementAt(2))[6], '');
  });

  test('accuracy_counts_only_classified_photographs', () {
    final report = fieldSessionReport([
      labelled('IMG_a.jpg', 'Argilosa', read: 'Argilosa'),
      labelled('IMG_b.jpg', 'Argilosa', read: 'Argilosa'),
      labelled('IMG_c.jpg', 'Argilosa', read: 'Muito Argilosa'),
      labelled(
        'IMG_d.jpg',
        'Argilosa',
        cause: ClassificationFailureCause.sheetNotFound,
      ),
    ], classes: classes);

    expect(report, contains('Argilosa: 2 of 3 classified right (1 refused)'));
    expect(report, contains('Refused: `sheetNotFound` 1'));
  });

  test('the_confusion_matrix_has_every_class', () {
    final report = fieldSessionReport([
      labelled('IMG_a.jpg', 'Arenosa', read: 'Muito Argilosa'),
      labelled('IMG_b.jpg', 'Media', read: 'Muito Argilosa'),
      labelled('IMG_c.jpg', 'Argilosa', read: 'Argilosa'),
      labelled(
        'IMG_d.jpg',
        'Media',
        cause: ClassificationFailureCause.photographTooCoarse,
      ),
    ], classes: classes);

    List<String> cells(String row) =>
        row.split('|').map((c) => c.trim()).toList();
    final lines = report.split('\n');
    final header = lines.indexWhere((l) => l.startsWith('| Expected \\ Read'));
    expect(
      cells(lines[header]).where((c) => c.isNotEmpty),
      ['Expected \\ Read', ...classes],
    );
    final matrix = lines.sublist(header + 2, header + 2 + classes.length);
    expect(matrix.map((row) => cells(row)[1]), classes);
    final total = matrix
        .expand((row) => cells(row).skip(2))
        .where((c) => c.isNotEmpty)
        .map(int.parse)
        .reduce((a, b) => a + b);
    expect(total, 3);
  });

  test('an_unlabelled_folder_reports_as_before', () {
    final report = fieldSessionReport([
      _refused('IMG_a.jpg', ClassificationFailureCause.sheetNotFound),
    ], classes: classes);

    expect(report, isNot(contains('Expected')));
    expect(report.trim().split('\n').last, '0 of 1 classified');
  });

  Map<String, dynamic> exportOf(Directory root, String name) {
    final manifest =
        jsonDecode(
              File('${root.path}/export/manifest.json').readAsStringSync(),
            )
            as List;
    return manifest.cast<Map<String, dynamic>>().firstWhere(
      (row) => row['source'] == name,
      orElse: () => <String, dynamic>{},
    );
  }

  test('the_export_is_at_the_canonical_scale', () async {
    // A synthetic sheet three times finer than its fixture: finer than the
    // canonical, so the export is a reduction.
    final fixture = img.decodeJpg(
      File('$sheetFixtures/sheet_frontal.jpg').readAsBytesSync(),
    )!;
    final root = Directory.systemTemp.createTempSync('field_export_');
    addTearDown(() => root.deleteSync(recursive: true));
    final fine = img.copyResize(
      fixture,
      width: fixture.width * 3,
      height: fixture.height * 3,
      interpolation: img.Interpolation.linear,
    );
    final path = '${root.path}/Media/fine.jpg';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(fine, quality: 95));

    await readFieldSession(root.path, exportDir: '${root.path}/export');

    final measurement = a4SheetMeasurer(
      InferenceService.frameOf(img.decodeJpg(File(path).readAsBytesSync())!),
    ).measurement!;
    final row = exportOf(root, 'fine.jpg');
    final canonical = (row['canonical_mm_per_px'] as num).toDouble();
    final ratio = measurement.mmPerPx / canonical;
    expect(measurement.mmPerPx, lessThan(canonical));
    expect(row['upsampled'], isFalse);
    expect(row['class'], 'Media');
    expect(row['sample'], 'Media');
    final png = img.decodePng(
      File('${root.path}/export/${row['file']}').readAsBytesSync(),
    )!;
    expect(png.width, roundHalfEven(measurement.frame.width * ratio));
    expect(png.height, roundHalfEven(measurement.frame.height * ratio));
    for (final (key, value) in [
      ('centre_y', measurement.centreYPx),
      ('centre_x', measurement.centreXPx),
      ('diameter', measurement.diameterPx),
    ]) {
      expect((row[key] as num).toDouble(), closeTo(value * ratio, 1e-9));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a_coarse_photograph_is_exported_upsampled', () async {
    final root = tree({'Argilosa/S5/coarse.jpg': 'sheet_frontal.jpg'});

    final read = await readFieldSession(
      root.path,
      exportDir: '${root.path}/export',
    );

    expect(
      read.single.report.cause,
      ClassificationFailureCause.photographTooCoarse,
    );
    final row = exportOf(root, 'coarse.jpg');
    expect(row['upsampled'], isTrue);
    expect((row['measured_mm_per_px'] as num).toDouble(), read.single.mmPerPx);
    expect(row['sample'], 'S5');
  });

  test('a_refused_photograph_is_not_exported', () async {
    final root = tree({
      'Arenosa/cropped.jpg': 'sheet_cropped.jpg',
      'Arenosa/frontal.jpg': 'sheet_frontal.jpg',
    });

    await readFieldSession(root.path, exportDir: '${root.path}/export');

    expect(exportOf(root, 'cropped.jpg'), isEmpty);
    expect(
      Directory(
        '${root.path}/export',
      ).listSync().where((f) => f.path.endsWith('.png')),
      hasLength(1),
    );
  });

  test('exported_files_never_collide', () async {
    final root = tree({
      'Media/S1/a.jpg': 'sheet_frontal.jpg',
      'Arenosa/S1/a.jpg': 'sheet_frontal.jpg',
      'Argilosa/a.jpg': 'sheet_frontal.jpg',
      'Argilosa/Argilosa/a.jpg': 'sheet_frontal.jpg',
    });

    await readFieldSession(root.path, exportDir: '${root.path}/export');

    final manifest =
        jsonDecode(File('${root.path}/export/manifest.json').readAsStringSync())
            as List;
    final files = [for (final row in manifest) row['file'] as String];
    expect(files.toSet(), hasLength(4));
    expect(
      Directory('${root.path}/export')
          .listSync()
          .where((f) => f.path.endsWith('.png')),
      hasLength(4),
    );
  });
}
