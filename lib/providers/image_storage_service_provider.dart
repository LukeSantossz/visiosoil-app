import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/image_storage_service.dart';

/// Exposes the [ImageStorageService] used to persist captured photos into
/// stable app storage. Override in tests to avoid touching the filesystem.
final imageStorageServiceProvider = Provider<ImageStorageService>((ref) {
  return DefaultImageStorageService();
});
