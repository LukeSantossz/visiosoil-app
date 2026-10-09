import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// The A4-sheet reader against real photographs (SPEC 0140, SPEC 0144): six
/// taken on 2026-10-05 on a pale table, reduced to a 1024 px long side. The
/// corners of each sheet were measured on the full-resolution original, so
/// nothing here shares the reader's mathematics.
const _fixtures = 'test/fixtures/sheet_photos';

typedef _Point = ({double x, double y});

final List<Map<String, dynamic>> _photos =
    ((jsonDecode(File('$_fixtures/expected.json').readAsStringSync())
                as Map<String, dynamic>)['photos']
            as List)
        .cast<Map<String, dynamic>>();

final _decoded = <String, RgbFrame>{};

RgbFrame _frame(Map<String, dynamic> photo) =>
    _decoded.putIfAbsent(photo['name'] as String, () {
      final frame = InferenceService.frameOf(
        img.decodeJpg(File('$_fixtures/${photo['file']}').readAsBytesSync())!,
      );
      expect([frame.width, frame.height], [photo['width'], photo['height']]);
      return frame;
    });

List<_Point> _annotated(Map<String, dynamic> photo) => [
  for (final corner in photo['corners'] as List)
    (x: (corner[0] as num).toDouble(), y: (corner[1] as num).toDouble()),
];

double _distance(_Point a, _Point b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// The mean length of the quadrilateral's two longer opposite edges, which is
/// what maps to the sheet's 297 mm.
double _longEdgePx(List<_Point> q) => math.max(
  (_distance(q[0], q[1]) + _distance(q[2], q[3])) / 2,
  (_distance(q[1], q[2]) + _distance(q[3], q[0])) / 2,
);

/// The reader finds the sheet in [frame] where [annotated] says it lies: each
/// corner within 1 % of the long side, matched as a set both ways, and the
/// scale it reads within 1 % of the annotated corners' scale.
void _expectFoundWhereItLies(
  String label,
  RgbFrame frame,
  List<_Point> annotated,
) {
  final result = findSheet(frame);
  expect(
    result.refusal,
    isNull,
    reason: '$label was refused as ${result.refusal}',
  );
  final found = result.corners!.points;
  expect(found, hasLength(4), reason: label);

  final tolerance = 0.01 * math.max(frame.width, frame.height);
  for (final (from, to, which) in [
    (found, annotated, 'found'),
    (annotated, found, 'annotated'),
  ]) {
    for (final corner in from) {
      final nearest = to.map((p) => _distance(p, corner)).reduce(math.min);
      expect(
        nearest,
        lessThanOrEqualTo(tolerance),
        reason:
            '$label: the $which corner (${corner.x.toStringAsFixed(1)}, '
            '${corner.y.toStringAsFixed(1)}) is '
            '${nearest.toStringAsFixed(2)} px from the nearest match',
      );
    }
  }

  final read = rectifySheet(frame, result.corners!).mmPerPx;
  final truth = sheetHeightMm / _longEdgePx(annotated);
  expect(
    (read - truth).abs() / truth,
    lessThanOrEqualTo(0.01),
    reason: '$label: $read mm/px against $truth',
  );
}

RgbFrame _quarterTurned(RgbFrame frame) {
  final width = frame.height;
  final rgb = Uint8List(frame.rgb.length);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final from = (y * frame.width + x) * 3;
      final to = (x * width + (frame.height - 1 - y)) * 3;
      rgb[to] = frame.rgb[from];
      rgb[to + 1] = frame.rgb[from + 1];
      rgb[to + 2] = frame.rgb[from + 2];
    }
  }
  return RgbFrame(width, frame.width, rgb);
}

RgbFrame _mirrored(RgbFrame frame) {
  final rgb = Uint8List(frame.rgb.length);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final from = (y * frame.width + x) * 3;
      final to = (y * frame.width + (frame.width - 1 - x)) * 3;
      rgb[to] = frame.rgb[from];
      rgb[to + 1] = frame.rgb[from + 1];
      rgb[to + 2] = frame.rgb[from + 2];
    }
  }
  return RgbFrame(frame.width, frame.height, rgb);
}

RgbFrame _darkened(RgbFrame frame) => RgbFrame(
  frame.width,
  frame.height,
  [for (final value in frame.rgb) (value * 85 + 50) ~/ 100].toUint8List(),
);

RgbFrame _noisy(RgbFrame frame) {
  final random = math.Random(140);
  return RgbFrame(
    frame.width,
    frame.height,
    [
      for (final value in frame.rgb)
        (value + random.nextInt(17) - 8).clamp(0, 255),
    ].toUint8List(),
  );
}

int _reducedSide(int side) => (side * 0.75).round();

/// A reduction to 75 %, by bilinear sampling with pixel centres aligned, so a
/// point at x moves to (x + 0.5) * scale - 0.5.
RgbFrame _reduced(RgbFrame frame) {
  final width = _reducedSide(frame.width);
  final height = _reducedSide(frame.height);
  final rgb = Uint8List(width * height * 3);
  double source(int to, int toSide, int fromSide) =>
      ((to + 0.5) * fromSide / toSide - 0.5)
          .clamp(0.0, fromSide - 1.0)
          .toDouble();
  for (var y = 0; y < height; y++) {
    final sy = source(y, height, frame.height);
    final y0 = math.min(sy.floor(), frame.height - 2);
    final fy = sy - y0;
    for (var x = 0; x < width; x++) {
      final sx = source(x, width, frame.width);
      final x0 = math.min(sx.floor(), frame.width - 2);
      final fx = sx - x0;
      for (var c = 0; c < 3; c++) {
        double at(int px, int py) =>
            frame.rgb[(py * frame.width + px) * 3 + c].toDouble();
        final top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx;
        final bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx;
        rgb[(y * width + x) * 3 + c] = (top * (1 - fy) + bottom * fy).round();
      }
    }
  }
  return RgbFrame(width, height, rgb);
}

/// [frame] with columns [from] to [to] of every row replaced by a linear ramp
/// between the two end columns, so no step is left between them (SPEC 0144).
RgbFrame _ramped(RgbFrame frame, int from, int to) {
  final rgb = Uint8List.fromList(frame.rgb);
  for (var y = 0; y < frame.height; y++) {
    for (var c = 0; c < 3; c++) {
      final start = frame.rgb[(y * frame.width + from) * 3 + c];
      final end = frame.rgb[(y * frame.width + to) * 3 + c];
      for (var x = from; x <= to; x++) {
        final t = (x - from) / (to - from);
        rgb[(y * frame.width + x) * 3 + c] = (start * (1 - t) + end * t)
            .round();
      }
    }
  }
  return RgbFrame(frame.width, frame.height, rgb);
}

extension on List<int> {
  Uint8List toUint8List() => Uint8List.fromList(this);
}

/// The five variants of SPEC 0140, each with the move it makes of a point.
final _variants =
    <
      ({
        String name,
        RgbFrame Function(RgbFrame) frame,
        _Point Function(_Point, RgbFrame original) corner,
      })
    >[
      (
        name: 'a quarter turn',
        frame: _quarterTurned,
        corner: (c, original) => (x: original.height - 1 - c.y, y: c.x),
      ),
      (
        name: 'a mirror image',
        frame: _mirrored,
        corner: (c, original) => (x: original.width - 1 - c.x, y: c.y),
      ),
      (name: 'a darkening to 85 %', frame: _darkened, corner: (c, _) => c),
      (name: 'noise of ±8 grey levels', frame: _noisy, corner: (c, _) => c),
      (
        name: 'a reduction to 75 %',
        frame: _reduced,
        corner: (c, original) => (
          x: (c.x + 0.5) * _reducedSide(original.width) / original.width - 0.5,
          y:
              (c.y + 0.5) * _reducedSide(original.height) / original.height -
              0.5,
        ),
      ),
    ];

Iterable<Map<String, dynamic>> get _sheets =>
    _photos.where((photo) => photo['expected'] == 'sheet');

Iterable<Map<String, dynamic>> get _refused =>
    _photos.where((photo) => photo['expected'] != 'sheet');

void main() {
  test('the_fixtures_hold_five_sheets_and_one_refusal', () {
    expect(_sheets, hasLength(5));
    expect(_refused.map((photo) => photo['expected']), ['cropped']);
  });

  test('a_real_sheet_is_found_where_it_lies', () {
    for (final photo in _sheets) {
      _expectFoundWhereItLies(
        photo['name'] as String,
        _frame(photo),
        _annotated(photo),
      );
    }
  });

  test('a_real_photograph_without_a_true_edge_is_refused', () {
    for (final photo in _refused) {
      expect(
        findSheet(_frame(photo)).refusal,
        SheetRefusal.values.byName(photo['expected'] as String),
        reason: '${photo['name']}: ${photo['note']}',
      );
    }
  });

  test('the_verdict_survives_the_variants', () {
    for (final variant in _variants) {
      for (final photo in _photos) {
        final original = _frame(photo);
        final frame = variant.frame(original);
        final label = '${photo['name']} under ${variant.name}';
        if (photo['expected'] == 'sheet') {
          _expectFoundWhereItLies(label, frame, [
            for (final c in _annotated(photo)) variant.corner(c, original),
          ]);
        } else {
          expect(
            findSheet(frame).refusal,
            SheetRefusal.values.byName(photo['expected'] as String),
            reason: label,
          );
        }
      }
    }
  });

  // On 160808 the paper's right edge lies at x ≈ 761 and the table's own
  // border at x ≈ 797. With the paper's edge ramped away, the first step past
  // the gradient is the table's border, and a sheet read there is about 7 %
  // too wide. The surface changes across the new corners, so it is refused.
  test('an_erased_paper_edge_is_not_read_at_the_table_border', () {
    final photo = _photos.singleWhere((photo) => photo['name'] == '160808');
    final erased = _ramped(_frame(photo), 735, 785);
    expect(
      findSheet(erased).refusal,
      SheetRefusal.notFound,
      reason: '160808 with its right paper edge erased',
    );
    for (final variant in _variants) {
      expect(
        findSheet(variant.frame(erased)).refusal,
        SheetRefusal.notFound,
        reason:
            '160808 with its right paper edge erased, under ${variant.name}',
      );
    }
  });
}
