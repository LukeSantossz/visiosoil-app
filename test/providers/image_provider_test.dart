import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/providers/image_provider.dart';

void main() {
  group('ImageNotifier.clearIfPath', () {
    test('clears the selection when it still holds the given path', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(imageProvider.notifier);
      notifier.setImage(File('/a.jpg'));

      notifier.clearIfPath('/a.jpg');

      expect(container.read(imageProvider).file, isNull);
    });

    test('keeps a newer selection when the path no longer matches', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(imageProvider.notifier);
      notifier.setImage(File('/newer.jpg'));

      notifier.clearIfPath('/older.jpg');

      expect(container.read(imageProvider).file?.path, '/newer.jpg');
    });
  });
}
