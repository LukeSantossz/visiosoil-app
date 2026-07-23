// Unit tests for the capture state model (#120): the composite CaptureUiState
// that replaced the five scattered booleans + request token.
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/capture_ui_state.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';

void main() {
  test('defaults are idle axes, guards off, generation 0, no permission', () {
    const s = CaptureUiState();

    expect(s.location, LocationStatus.idle);
    expect(s.classification, ClassificationStatus.idle);
    expect(s.isCapturing, isFalse);
    expect(s.isSaving, isFalse);
    expect(s.generation, 0);
    expect(s.cameraPermission, isNull);
    expect(s.isLocating, isFalse);
    expect(s.isClassifying, isFalse);
    expect(s.classificationFailed, isFalse);
  });

  test('derived getters track their status axes independently', () {
    const both = CaptureUiState(
      location: LocationStatus.loading,
      classification: ClassificationStatus.running,
    );
    expect(both.isLocating, isTrue);
    expect(both.isClassifying, isTrue);
    expect(both.classificationFailed, isFalse);

    const failed = CaptureUiState(classification: ClassificationStatus.failed);
    expect(failed.classificationFailed, isTrue);
    expect(failed.isClassifying, isFalse);
  });

  test('copyWith keeps unspecified fields and clears a nullable when passed null',
      () {
    const s = CaptureUiState(
      address: 'São Paulo',
      latitude: 1,
      longitude: 2,
      generation: 3,
    );

    final kept = s.copyWith(isSaving: true);
    expect(kept.address, 'São Paulo');
    expect(kept.latitude, 1);
    expect(kept.generation, 3);
    expect(kept.isSaving, isTrue);

    final cleared = s.copyWith(address: null);
    expect(cleared.address, isNull);
    expect(cleared.latitude, 1, reason: 'other nullables stay untouched');
  });

  test('startingCapture advances the generation and resets both async axes', () {
    const s = CaptureUiState(
      location: LocationStatus.resolved,
      latitude: 1,
      longitude: 2,
      address: 'x',
      classification: ClassificationStatus.done,
      classificationResult:
          InferenceResult(textureClass: 'Argilosa', confidenceScore: 0.9),
      isCapturing: true,
      cameraPermission: AppPermissionStatus.granted,
      generation: 4,
    );

    final fresh = s.startingCapture(5);

    expect(fresh.generation, 5);
    expect(fresh.location, LocationStatus.idle);
    expect(fresh.latitude, isNull);
    expect(fresh.longitude, isNull);
    expect(fresh.address, isNull);
    expect(fresh.classification, ClassificationStatus.idle);
    expect(fresh.classificationResult, isNull);
    // Transient guards and the permission are deliberately left untouched.
    expect(fresh.isCapturing, isTrue);
    expect(fresh.cameraPermission, AppPermissionStatus.granted);
  });
}
