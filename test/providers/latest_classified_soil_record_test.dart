import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

SoilRecord _classified(int id) => SoilRecord(
      id: id,
      imagePath: '$id.png',
      timestamp: '2026-06-2${id}T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

SoilRecord _unclassified(int id) => SoilRecord(
      id: id,
      imagePath: '$id.png',
      timestamp: '2026-06-2${id}T12:00:00Z',
    );

Future<SoilRecord?> _latestClassified(List<SoilRecord> records) async {
  final container = ProviderContainer(
    overrides: [
      soilRecordsStreamProvider.overrideWith((ref) => Stream.value(records)),
    ],
  );
  addTearDown(container.dispose);
  // Keep the derived provider subscribed while the stream emits, then flush the
  // microtask queue and read the resolved value (awaiting `.future` hangs on
  // this Riverpod version).
  final sub = container.listen(latestClassifiedSoilRecordProvider, (_, _) {});
  addTearDown(sub.close);
  await pumpEventQueue();
  return container.read(latestClassifiedSoilRecordProvider).value;
}

void main() {
  test('returns the latest classified record, skipping a newer unclassified one',
      () async {
    // watchAll is most-recent-first: the newest record is unclassified.
    final latest = await _latestClassified([
      _unclassified(3),
      _classified(2),
      _classified(1),
    ]);

    expect(latest?.id, 2);
  });

  test('returns null when no record carries a classification', () async {
    final latest = await _latestClassified([
      _unclassified(2),
      _unclassified(1),
    ]);

    expect(latest, isNull);
  });

  test('returns null when there are no records', () async {
    final latest = await _latestClassified(const []);

    expect(latest, isNull);
  });
}
