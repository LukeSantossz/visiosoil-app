import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/image_storage_service.dart';
import 'package:visiosoil_app/providers/image_storage_service_provider.dart';

void main() {
  test('imageStorageServiceProvider exposes a DefaultImageStorageService', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final service = container.read(imageStorageServiceProvider);

    expect(service, isA<DefaultImageStorageService>());
  });
}
