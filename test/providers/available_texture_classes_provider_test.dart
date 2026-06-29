// Tests for [availableTextureClassesProvider]: the history texture-filter chip
// source must reflect database changes reactively, not a one-shot snapshot.
//
// Runs on the Dart VM with an in-memory SQLite database, the same setup as the
// repository tests.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/database/app_database.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/database_provider.dart';
import 'package:visiosoil_app/providers/image_storage_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../support/fake_image_storage_service.dart';

void main() {
  group('availableTextureClassesProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    String ts() => DateTime.utc(2026, 1, 1).toIso8601String();

    SoilRecord sample({String? textureClass, String imagePath = '/img.jpg'}) {
      return SoilRecord(
        imagePath: imagePath,
        timestamp: ts(),
        textureClass: textureClass,
        confidenceScore: textureClass == null ? null : 0.9,
      );
    }

    // Lets the Drift watch() stream emit and the derived provider recompute,
    // mirroring the delay used in the repository stream tests.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    List<String> classes() =>
        container.read(availableTextureClassesProvider).value ?? const [];

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          imageStorageServiceProvider.overrideWithValue(FakeImageStorageService()),
        ],
      );
      addTearDown(container.dispose);
      // Keep the provider and its underlying stream subscription alive.
      final sub = container.listen(availableTextureClassesProvider, (_, _) {});
      addTearDown(sub.close);
    });

    test('is empty when there are no records', () async {
      await settle();
      expect(classes(), isEmpty);
    });

    test('adds a class reactively when a new classified record is created',
        () async {
      await settle();
      expect(classes(), isEmpty);

      await container
          .read(soilRecordRepositoryProvider)
          .create(sample(textureClass: 'Arenosa', imagePath: '/a.jpg'));
      await settle();

      expect(classes(), contains('Arenosa'));
    });

    test('returns distinct, sorted classes and ignores unclassified records',
        () async {
      await settle();
      final repo = container.read(soilRecordRepositoryProvider);
      await repo.create(sample(textureClass: 'Arenosa', imagePath: '/a.jpg'));
      await repo.create(sample(textureClass: 'Argilosa', imagePath: '/b.jpg'));
      await repo.create(sample(textureClass: 'Arenosa', imagePath: '/c.jpg'));
      await repo.create(sample(imagePath: '/d.jpg')); // unclassified
      await settle();

      expect(classes(), ['Arenosa', 'Argilosa']);
    });

    test('removes a class when its last record is deleted', () async {
      await settle();
      final repo = container.read(soilRecordRepositoryProvider);
      final saved = await repo
          .create(sample(textureClass: 'Arenosa', imagePath: '/a.jpg'));
      await settle();
      expect(classes(), contains('Arenosa'));

      await repo.deleteById(saved.id!);
      await settle();

      expect(classes(), isEmpty);
    });
  });
}
