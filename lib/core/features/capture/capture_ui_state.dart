import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';

/// Status of the location fetch for the current capture. Runs concurrently with
/// (and independently of) classification.
enum LocationStatus { idle, loading, resolved, unavailable }

/// Status of the texture classification for the current capture. Runs
/// concurrently with (and independently of) the location fetch.
enum ClassificationStatus { idle, running, done, failed }

/// Sentinel so [CaptureUiState.copyWith] can distinguish "leave unchanged" from
/// "set to null" for its nullable fields.
const Object _unset = Object();

/// Immutable UI state for the capture screen.
///
/// Location and classification run in parallel (`Future.wait`), so they are
/// modelled as two independent status axes rather than one flat, mutually
/// exclusive enum. [isCapturing] and [isSaving] are transient re-entry guards,
/// and [generation] is the monotonic token used to ignore results from a
/// superseded or discarded capture.
class CaptureUiState {
  const CaptureUiState({
    this.location = LocationStatus.idle,
    this.latitude,
    this.longitude,
    this.address,
    this.classification = ClassificationStatus.idle,
    this.classificationResult,
    this.isCapturing = false,
    this.isSaving = false,
    this.generation = 0,
    this.cameraPermission,
  });

  final LocationStatus location;
  final double? latitude;
  final double? longitude;
  final String? address;

  final ClassificationStatus classification;
  final InferenceResult? classificationResult;

  final bool isCapturing;
  final bool isSaving;
  final int generation;
  final AppPermissionStatus? cameraPermission;

  bool get isLocating => location == LocationStatus.loading;
  bool get isClassifying => classification == ClassificationStatus.running;
  bool get classificationFailed => classification == ClassificationStatus.failed;

  /// Returns a copy with the given fields replaced. Nullable fields left as the
  /// [_unset] sentinel keep their current value; pass `null` explicitly to clear.
  CaptureUiState copyWith({
    LocationStatus? location,
    Object? latitude = _unset,
    Object? longitude = _unset,
    Object? address = _unset,
    ClassificationStatus? classification,
    Object? classificationResult = _unset,
    bool? isCapturing,
    bool? isSaving,
    int? generation,
    Object? cameraPermission = _unset,
  }) {
    return CaptureUiState(
      location: location ?? this.location,
      latitude:
          identical(latitude, _unset) ? this.latitude : latitude as double?,
      longitude:
          identical(longitude, _unset) ? this.longitude : longitude as double?,
      address: identical(address, _unset) ? this.address : address as String?,
      classification: classification ?? this.classification,
      classificationResult: identical(classificationResult, _unset)
          ? this.classificationResult
          : classificationResult as InferenceResult?,
      isCapturing: isCapturing ?? this.isCapturing,
      isSaving: isSaving ?? this.isSaving,
      generation: generation ?? this.generation,
      cameraPermission: identical(cameraPermission, _unset)
          ? this.cameraPermission
          : cameraPermission as AppPermissionStatus?,
    );
  }

  /// Resets both async axes and their payloads for a fresh capture, keeping the
  /// guards and permission untouched. [generation] advances so late results
  /// from the previous capture are ignored.
  CaptureUiState startingCapture(int newGeneration) {
    return copyWith(
      generation: newGeneration,
      location: LocationStatus.idle,
      latitude: null,
      longitude: null,
      address: null,
      classification: ClassificationStatus.idle,
      classificationResult: null,
    );
  }
}
