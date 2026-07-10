// Tests for [availableTextureClassesProvider]: the history texture-filter chip
// source must reflect database changes reactively, not a one-shot snapshot.
//
// Runs on the Dart VM with an in-memory SQLite database, the same setup as the
// repository tests.
import 'dart:async';

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

    // Resolves with the provider's class list once it satisfies [test], firing
    // immediately when the current value already does. Event-driven: it waits
    // for the Drift stream to propagate to the provider instead of sleeping a
    // fixed interval, removing a latent CI-flakiness source.
    Future<List<String>> classesMatching(bool Function(List<String>) test) {
      final completer = Completer<List<String>>();
      final sub = container.listen<AsyncValue<List<String>>>(
        availableTextureClassesProvider,
        (_, next) {
          final value = next.value;
          if (value != null && !completer.isCompleted && test(value)) {
            completer.complete(value);
          }
        },
        fireImmediately: true,
      );
      return completer.future.whenComplete(sub.close);
    }

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
      expect(await classesMatching((c) => c.isEmpty), isEmpty);
    });

    test('adds a class reactively when a new classified record is created',
        () async {
      expect(await classesMatching((c) => c.isEmpty), isEmpty);

      await container
          .read(soilRecordRepositoryProvider)
          .create(sample(textureClass: 'Arenosa', imagePath: '/a.jpg'));

      expect(
        await classesMatching((c) => c.contains('Arenosa')),
        contains('Arenosa'),
      );
    });

    test('returns distinct, sorted classes and ignores unclassified records',
        () async {
      final repo = container.read(soilRecordRepositoryProvider);
      await repo.create(sample(textureClass: 'Arenosa', imagePath: '/a.jpg'));
      await repo.create(sample(textureClass: 'Argilosa', imagePath: '/b.jpg'));
      await repo.create(sample(textureClass: 'Arenosa', imagePath: '/c.jpg'));
      await repo.create(sample(imagePath: '/d.jpg')); // unclassified

      expect(
        await classesMatching((c) => c.length == 2),
        ['Arenosa', 'Argilosa'],
      );
    });

    test('removes a class when its last record is deleted', () async {
      final repo = container.read(soilRecordRepositoryProvider);
      final saved = await repo
          .create(sample(textureClass: 'Arenosa', imagePath: '/a.jpg'));
      expect(
        await classesMatching((c) => c.contains('Arenosa')),
        contains('Arenosa'),
      );

      await repo.deleteById(saved.id!);

      expect(await classesMatching((c) => c.isEmpty), isEmpty);
    });
  });
}
