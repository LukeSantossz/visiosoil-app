import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/capture_guide_store.dart';

/// The capture guide's seen-flag store. Overridden with a fake in tests.
final captureGuideStoreProvider = Provider<CaptureGuideStore>(
  (ref) => SharedPreferencesCaptureGuideStore(),
);
