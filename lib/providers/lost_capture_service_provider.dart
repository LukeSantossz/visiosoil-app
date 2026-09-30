import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/lost_capture_service.dart';

/// Exposes the [LostCaptureService] the home screen asks, on arrival, for a
/// photograph lost when Android killed the app mid-capture. Override in tests
/// to answer without the plugin.
final lostCaptureServiceProvider = Provider<LostCaptureService>((ref) {
  return ImagePickerLostCaptureService();
});
