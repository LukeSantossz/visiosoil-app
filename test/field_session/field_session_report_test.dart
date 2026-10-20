import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

import 'field_session_report.dart';

/// The table a field session is recorded with (SPEC 0170).
FieldPhotograph _classified(String name, String textureClass, double share) =>
    (
      name: name,
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
}
