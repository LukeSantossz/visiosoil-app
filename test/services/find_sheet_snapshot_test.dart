import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// Pins every decision `findSheet` took on each sheet fixture before it began
/// recording the sides a cropped sheet runs off (SPEC 0169): the corners and
/// the refusal, as `main` produced them, so recording a side can change none.
void main() {
  test('find_sheet_decides_as_before', () {
    final snapshot = (jsonDecode(
      File('test/fixtures/sheet/find_sheet_snapshot.json').readAsStringSync(),
    ) as Map<String, dynamic>);
    expect(snapshot, hasLength(17));
    for (final MapEntry(key: name, value: entry) in snapshot.entries) {
      final expected = entry as Map<String, dynamic>;
      final frame = InferenceService.frameOf(img.decodeJpg(
        File('test/fixtures/$name').readAsBytesSync(),
      )!);
      final result = findSheet(frame);
      expect(result.refusal?.name, expected['refusal'], reason: name);
      final corners = expected['corners'] as List?;
      if (corners == null) {
        expect(result.corners, isNull, reason: name);
        continue;
      }
      final found = result.corners!.points;
      expect(found, hasLength(4), reason: name);
      for (var i = 0; i < 4; i++) {
        final point = corners[i] as List;
        expect(found[i].x, closeTo((point[0] as num).toDouble(), 1e-9),
            reason: '$name corner $i');
        expect(found[i].y, closeTo((point[1] as num).toDouble(), 1e-9),
            reason: '$name corner $i');
      }
    }
  });
}
