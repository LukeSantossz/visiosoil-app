import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/capture_ui_state.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/widgets/camera_permission_denied_view.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_actions.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_image_preview.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/details/widgets/labels_dialog.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_error_block.dart';
import 'package:visiosoil_app/core/features/capture/widgets/processing_view.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/gallery_saver.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/location_service.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/models/confidence_level.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';
import 'package:visiosoil_app/providers/capture_preferences_provider.dart';
import 'package:visiosoil_app/providers/image_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/just_saved_record_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import 'package:visiosoil_app/providers/soil_sample_provider.dart';

/// A device location reading: coordinates, the fix's accuracy radius in metres
/// (null when the device reported no usable one, SPEC 0148) and a
/// reverse-geocoded address.
typedef LocationReading = ({
  double latitude,
  double longitude,
  double? accuracy,
  String address,
});

/// Resolves the current device location, or `null` when unavailable.
typedef LocationResolver = Future<LocationReading?> Function();

/// Opens the camera and returns the captured image, or `null` if cancelled.
typedef CameraImagePicker = Future<XFile?> Function();

/// Opens the guided camera and returns what it popped, or `null` for a back
/// gesture (SPEC 0165).
typedef GuidedCameraOpener =
    Future<GuidedCaptureResult?> Function(BuildContext context);

/// Reports a camera permission status.
typedef CameraPermissionProbe = Future<AppPermissionStatus> Function();

/// Deletes a file the camera picker handed the screen.
typedef PickedFileDeleter = Future<void> Function(String path);

/// Deletes the picker's file at [path]. An absent file counts as deleted.
Future<void> deletePickedFile(String path) async {
  try {
    await File(path).delete();
  } on PathNotFoundException {
    // Already gone; nothing is left to remove.
  }
}

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({
    super.key,
    this.pickFromCamera,
    this.openGuidedCamera,
    this.pickFromSystemCamera,
    this.locate,
    this.checkCameraPermission,
    this.requestCameraPermission,
    this.deletePickedFile,
    this.initialImagePath,
  });

  /// Test seams; each defaults to the real platform implementation.
  final CameraImagePicker? pickFromCamera;
  final LocationResolver? locate;
  final CameraPermissionProbe? checkCameraPermission;
  final CameraPermissionProbe? requestCameraPermission;
  final PickedFileDeleter? deletePickedFile;

  /// Used only when [pickFromCamera] is not injected: the guided camera, and
  /// the system camera it falls back to (SPEC 0165).
  final GuidedCameraOpener? openGuidedCamera;
  final CameraImagePicker? pickFromSystemCamera;

  /// A photograph to start with instead of opening the camera: one recovered
  /// after Android killed the app mid-capture (SPEC 0096).
  final String? initialImagePath;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  String? _processingClass;

  /// When the current result arrived: the draft result's time (SPEC 0196).
  DateTime? _resultAt;
  Completer<void>? _settlement;

  static const Duration _locationTimeout = Duration(seconds: 20);

  /// Single immutable UI state. Every mutation goes through
  /// `setState(() => _state = _state.copyWith(...))` (or a named transition),
  /// replacing the previously scattered booleans, payload fields, and request
  /// token. See [CaptureUiState] for why location and classification are
  /// independent axes rather than one flat enum.
  CaptureUiState _state = const CaptureUiState();

  /// The state as it stands, for a test to read what the screen does not show.
  @visibleForTesting
  CaptureUiState get uiState => _state;

  late final CameraImagePicker _pickFromCamera =
      widget.pickFromCamera ?? _defaultPickFromCamera;
  late final GuidedCameraOpener _openGuidedCamera =
      widget.openGuidedCamera ??
      (context) => context.push<GuidedCaptureResult>('/camera');
  late final CameraImagePicker _pickFromSystemCamera =
      widget.pickFromSystemCamera ?? _systemCameraPick;
  late final LocationResolver _locate = widget.locate ?? _defaultLocate;
  late final CameraPermissionProbe _checkCameraPermission =
      widget.checkCameraPermission ?? PermissionService.checkCamera;
  late final CameraPermissionProbe _requestCameraPermission =
      widget.requestCameraPermission ?? PermissionService.requestCamera;
  late final PickedFileDeleter _deletePickedFile =
      widget.deletePickedFile ?? deletePickedFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialImagePath = widget.initialImagePath;
    if (initialImagePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _useCapturedImage(initialImagePath);
      });
    }
  }

  @override
  void dispose() {
    _cancelSettlement();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Revalidates permission when the app returns to the foreground (e.g. after Settings)
    // Does not revalidate for `restricted` (iOS) since it cannot be changed by the user
    if (state == AppLifecycleState.resumed &&
        _state.cameraPermission == AppPermissionStatus.permanentlyDenied) {
      _recheckCameraPermission();
    }
  }

  /// The guided camera, and the system camera only when the guided one is
  /// unavailable (SPEC 0165, ADR 0028).
  Future<XFile?> _defaultPickFromCamera() async {
    final result = await _openGuidedCamera(context);
    return switch (result) {
      GuidedCaptureCaptured(:final file) => file,
      GuidedCaptureUnavailable() => _pickFromSystemCamera(),
      GuidedCaptureCancelled() || null => null,
    };
  }

  Future<XFile?> _systemCameraPick() => ImagePicker().pickImage(
    source: ImageSource.camera,
    // Drop EXIF (including GPS) at the source so stored originals carry no
    // uncontrolled location duplicate; the app never reads image metadata.
    requestFullMetadata: false,
  );

  Future<LocationReading?> _defaultLocate() async {
    final position = await LocationService.getCurrentLocation();
    final address = await LocationService.getAddressFromPosition(position);
    return (
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: LocationService.horizontalAccuracyOf(position),
      address: address,
    );
  }

  Future<void> _recheckCameraPermission() async {
    final status = await _checkCameraPermission();
    if (!mounted) return;

    if (status == AppPermissionStatus.granted) {
      setState(() => _state = _state.copyWith(cameraPermission: null));
    }
  }

  Future<void> _pickImage() async {
    // Re-entry guard: prevents a rapid double tap from opening two pickers
    // (and firing duplicate location/classification work). A retake tapped in
    // the same frame as a save does nothing (SPEC 0147).
    if (_state.isCapturing || _state.isSaving) return;
    _state = _state.copyWith(isCapturing: true);

    XFile? image;
    try {
      final status = await _checkCameraPermission();
      if (!mounted) return;

      if (status != AppPermissionStatus.granted) {
        final requestStatus = await _requestCameraPermission();
        if (!mounted) return;

        if (requestStatus != AppPermissionStatus.granted) {
          // A retake keeps the photograph in view: the denied view would hide
          // it, and back from there would discard it (SPEC 0147).
          if (ref.read(imageProvider).hasImage) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sem acesso à câmera. A foto atual foi mantida.'),
              ),
            );
            return;
          }
          setState(
            () => _state = _state.copyWith(cameraPermission: requestStatus),
          );
          return;
        }
      }
      // Clears the permission state if granted
      if (_state.cameraPermission != null) {
        setState(() => _state = _state.copyWith(cameraPermission: null));
      }

      if (!await _passCaptureGuide()) return;
      image = await _pickFromCamera();
    } catch (e) {
      developer.log('Camera capture failed: $e', name: 'CaptureScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir a câmera.')),
        );
      }
      return;
    } finally {
      _state = _state.copyWith(isCapturing: false);
    }

    if (!mounted || image == null) return;

    // The shutter's return; a recovered photograph gets none (SPEC 0126).
    unawaited(AppHaptics.confirm());
    final previous = ref.read(imageProvider).file;
    final replaced = _useCapturedImage(image.path);
    // A retake: the new photograph has replaced the previous one, whose picker
    // file goes as "Descartar" deletes it (SPEC 0147).
    if (previous != null && previous.path != image.path) {
      unawaited(_disposePickedFile(_deletePickedFile, previous.path));
    }
    await replaced;
  }

  /// Shows the capture guide before the first camera launch, and answers
  /// whether the camera may open: a guide already seen, or the guide's primary
  /// action, lets it; its back button does not (SPEC 0142). A flag that cannot
  /// be read counts as seen, so the store never keeps the camera closed.
  Future<bool> _passCaptureGuide() async {
    final bool seen;
    try {
      seen = await ref.read(captureGuideStoreProvider).hasSeenCaptureGuide();
    } on Exception catch (e) {
      developer.log(
        'Could not read the capture guide flag: $e',
        name: 'CaptureScreen',
      );
      return true;
    }
    if (seen) return true;
    if (!mounted) return false;
    final confirmed = await context.push<bool>('/capture-guide', extra: true);
    return mounted && confirmed == true;
  }

  /// Shows the photograph at [path] as the capture and runs location and
  /// classification on it, whether it was just picked or recovered after a
  /// restart.
  Future<void> _useCapturedImage(String path) async {
    ref.read(imageProvider.notifier).setImage(File(path));

    // Tags this capture so late results from a superseded one are ignored.
    final generation = _state.generation + 1;
    setState(() {
      _state = _state.startingCapture(generation);
      // A new photograph starts without the last draft's labels.
      _draftLabels = null;
    });

    // Runs location and classification in parallel (they are independent)
    await Future.wait([
      _fetchCurrentLocation(generation),
      _classifySoilTexture(path, generation),
    ]);
  }

  void _cancelSettlement() {
    final settlement = _settlement;
    if (settlement != null && !settlement.isCompleted) settlement.complete();
    _settlement = null;
    _processingClass = null;
  }

  Future<void> _classifySoilTexture(String imagePath, int generation) async {
    _cancelSettlement();
    if (mounted) {
      setState(
        () => _state = _state.copyWith(
          classification: ClassificationStatus.running,
          classificationPhase: null,
        ),
      );
    }

    ClassificationReport report;
    try {
      final inferenceService = ref.read(inferenceServiceProvider);
      // No deadline here: `classify` owns the only one, because it holds the
      // isolate handle and can stop the work. A second timeout at this layer
      // would abandon the future while the isolate kept running.
      report = await inferenceService.classify(
        imagePath,
        onPhase: (phase) {
          // A superseded capture's isolate may still be reporting.
          if (!mounted || generation != _state.generation) return;
          setState(() => _state = _state.copyWith(classificationPhase: phase));
        },
      );
    } catch (e) {
      // `classify` reports its failures rather than throwing, so this is a
      // defect in it; the screen still lands in the failed state.
      developer.log('Classification threw: $e', name: 'CaptureScreen');
      report = const ClassificationReport.failed(
        ClassificationFailureCause.computationError,
      );
    }
    if (report.cause != null) {
      developer.log(
        'Classification failed: ${report.cause!.name}',
        name: 'CaptureScreen',
      );
    }

    if (!mounted || generation != _state.generation) return;
    if (report.result != null) {
      final settlement = _settlement = Completer<void>();
      setState(() => _processingClass = report.result!.textureClass);
      await settlement.future;
      if (!mounted || generation != _state.generation) return;
      if (!context.palette.isSun &&
          !AppMotion.reduceMotion &&
          !MediaQuery.disableAnimationsOf(context)) {
        await Future<void>.delayed(AppMotion.slow);
      }
      if (!mounted || generation != _state.generation) return;
    }
    _resultAt = DateTime.now();
    setState(
      () => _state = _state.copyWith(
        classificationResult: report.result,
        classificationFailureCause: report.cause,
        classification: report.outcome == ClassificationOutcome.ok
            ? ClassificationStatus.done
            : ClassificationStatus.failed,
      ),
    );
    // A result arriving, by its confidence (redesign v11 §3.14); a failure's
    // chip names its cause instead.
    final arrived = report.result;
    if (report.outcome == ClassificationOutcome.ok && arrived != null) {
      final low =
          ConfidenceLevel.fromScore(arrived.confidenceScore) ==
          ConfidenceLevel.low;
      unawaited(low ? AppHaptics.confirm() : AppHaptics.result());
    }
  }

  Future<void> _fetchCurrentLocation(int generation) async {
    // Configurações' "Registrar localização" off: no fix is asked for and the
    // record saves without coordinates (SPEC 0208).
    if (!ref.read(recordLocationProvider)) {
      if (mounted && generation == _state.generation) {
        setState(
          () => _state = _state.copyWith(location: LocationStatus.unavailable),
        );
      }
      return;
    }
    if (mounted) {
      setState(
        () => _state = _state.copyWith(location: LocationStatus.loading),
      );
    }

    LocationReading? reading;
    try {
      reading = await _locate().timeout(
        _locationTimeout,
        onTimeout: () => null,
      );
    } catch (_) {
      // Location is optional: the record can be saved without coordinates.
      reading = null;
    }

    if (!mounted || generation != _state.generation) return;
    setState(() {
      if (reading != null) {
        _state = _state.copyWith(
          location: LocationStatus.resolved,
          latitude: reading.latitude,
          longitude: reading.longitude,
          horizontalAccuracy: reading.accuracy,
          address: reading.address,
        );
      } else {
        _state = _state.copyWith(location: LocationStatus.unavailable);
      }
    });
  }

  void _retryClassification() {
    // Mirrors the `_isCapturing`/`_isSaving` guards. The retry chip is only
    // rendered once a classification has failed, so a second tap is already
    // improbable; this closes the same-frame window where two taps hit the
    // chip before the rebuild removes it, each spawning its own isolate.
    if (_state.isClassifying) return;
    final image = ref.read(imageProvider).file;
    if (image == null) return;
    _classifySoilTexture(image.path, _state.generation);
  }

  Future<void> _saveRecord() async {
    // Guard against double-tap, and against a save tapped in the same frame
    // as a retry: the button's callback is from the last build, so it checks
    // the state it runs against (SPEC 0117). A save tapped while the camera is
    // open for a retake does nothing, as the photograph is about to change
    // (SPEC 0147).
    if (_state.isSaving || _state.isClassifying || _state.isCapturing) return;

    final selectedImage = ref.read(imageProvider);
    final image = selectedImage.file;
    if (image == null) return;

    // Capture the notifier and the deleter before the await so the post-save
    // cleanup never touches `ref` or `widget` after the widget is disposed.
    final imageNotifier = ref.read(imageProvider.notifier);
    final deletePicked = _deletePickedFile;
    final gallery = ref.read(saveToGalleryProvider)
        ? ref.read(gallerySaverProvider)
        : null;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _state = _state.copyWith(isSaving: true));

    SoilRecord? created;
    try {
      final String finalAddress =
          _state.address ?? AppStrings.addressUnavailable;
      final labelled = _draftRecord(image, null);
      final double? finalLatitude = _state.latitude;
      final double? finalLongitude = _state.longitude;

      created = await ref
          .read(soilRecordRepositoryProvider)
          .create(
            SoilRecord(
              imagePath: image.path,
              latitude: finalLatitude,
              longitude: finalLongitude,
              address: finalAddress,
              timestamp: DateTime.now().toIso8601String(),
              textureClass: _state.classificationResult?.textureClass,
              confidenceScore: _state.classificationResult?.confidenceScore,
              classDistribution: _state.classificationResult?.classDistribution,
              modelVersion: _state.classificationResult?.modelVersion,
              datasetVersion: _state.classificationResult?.datasetVersion,
              horizontalAccuracy: _state.horizontalAccuracy,
              // What "Corrigir" named on the draft (SPEC 0202).
              fieldName: labelled.fieldName,
              sampleLabel: labelled.sampleLabel,
              // The cause the chip named, kept for the record (SPEC 0173).
              classificationFailure: _state.classificationResult == null
                  ? _state.classificationFailureCause
                  : null,
            ),
          );
    } catch (e) {
      // A repository write failure must not leave the user without feedback:
      // surface it and keep the image (no clearImage, no navigation) so they
      // can retry.
      developer.log('Save failed: $e', name: 'CaptureScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar o registro. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _state = _state.copyWith(isSaving: false));
      }
    }

    // Only after a confirmed write, and outside the try so a post-save UI error
    // is never mis-reported as a save failure (which would prompt a retry and
    // write a duplicate). Clear via the captured notifier — even if the screen
    // was disposed mid-save — but only if the provider still holds the photo we
    // saved, so a slow write finishing after a newer capture does not wipe it.
    // Only the snackbar and the navigation need the widget still mounted.
    if (created != null) {
      unawaited(AppHaptics.confirm());
      imageNotifier.clearIfPath(image.path);
      // The record points at its durable copy now. A failed save never gets
      // here, so its retry still has the photograph.
      unawaited(_disposePickedFile(deletePicked, image.path));
      // The stored copy, already without EXIF, goes to the gallery; a refusal
      // leaves the record as it is (SPEC 0208).
      if (gallery != null) {
        unawaited(_copyToGallery(gallery, created.imagePath, messenger));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.resultSavedSnackbar)),
        );
        // Details pops its bookmark for this record (SPEC 0197).
        final createdId = created.id;
        if (createdId != null) {
          ref.read(justSavedRecordProvider.notifier).mark(createdId);
        }
        // Capture is replaced, so back from details returns to whatever
        // opened it (SPEC 0132).
        context.pushReplacement('/details', extra: created.id);
      }
    }
  }

  Future<void> _copyToGallery(
    GallerySaver gallery,
    String imagePath,
    ScaffoldMessengerState messenger,
  ) async {
    try {
      await gallery.save(imagePath);
    } on Object catch (e) {
      developer.log('Gallery save failed: $e', name: 'CaptureScreen');
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.gallerySaveFailed)),
      );
    }
  }

  void _discardImage() {
    _cancelSettlement();
    final picked = ref.read(imageProvider).file;
    // Invalidates any in-flight location/classification work for this capture.
    final generation = _state.generation + 1;
    ref.read(imageProvider.notifier).clearImage();
    setState(() {
      _state = _state.startingCapture(generation);
      // A new photograph starts without the last draft's labels.
      _draftLabels = null;
    });
    // A save in flight may still be copying the file; it deletes the file
    // itself once it succeeds.
    if (picked != null && !_state.isSaving) {
      unawaited(_disposePickedFile(_deletePickedFile, picked.path));
    }
  }

  /// Leaving capture discards its photograph, as "Descartar" does
  /// (SPEC 0146). It clears only once the page has left, so the photograph
  /// does not blank while it slides out, and with what it reads now, since the
  /// screen is disposed by then.
  void _discardOnLeave() {
    final picked = ref.read(imageProvider).file;
    if (picked == null) return;
    final imageNotifier = ref.read(imageProvider.notifier);
    final deletePicked = _deletePickedFile;
    // A save in flight deletes the file itself once it succeeds.
    final saving = _state.isSaving;
    final left = ModalRoute.of(context)?.completed ?? Future<void>.value();
    unawaited(
      left.then((_) {
        imageNotifier.clearIfPath(picked.path);
        if (!saving) unawaited(_disposePickedFile(deletePicked, picked.path));
      }),
    );
  }

  /// Deletes the picker's file once the screen no longer needs it, best
  /// effort (SPEC 0094). The file still carries the original EXIF, GPS
  /// included, which only the durable copy is stripped of (ADR 0005). A
  /// failure is logged and never fails the save or the discard.
  static Future<void> _disposePickedFile(
    PickedFileDeleter delete,
    String path,
  ) async {
    try {
      await delete(path);
    } catch (e) {
      developer.log(
        'Could not delete the picked file: $e',
        name: 'CaptureScreen',
      );
    }
  }

  void _retryCameraPermission() {
    setState(() => _state = _state.copyWith(cameraPermission: null));
    _pickImage();
  }

  /// The labels "Corrigir" gave the draft, kept for the save (SPEC 0202).
  ({String fieldName, String sampleLabel})? _draftLabels;

  Future<void> _editDraftLabels(SoilRecord draft) async {
    // A save has already taken the labels it writes (review of #436).
    if (_state.isSaving) return;
    final labels = await showLabelsDialog(context, draft);
    if (labels == null || !mounted) return;
    setState(() => _draftLabels = labels);
  }

  /// The record capture shows before a save: classified, or naming the cause
  /// it was not (SPEC 0196, SPEC 0202).
  SoilRecord _draftRecord(File image, InferenceResult? result) {
    final labels = _draftLabels;
    String? trimmed(String? text) =>
        text == null || text.trim().isEmpty ? null : text.trim();
    return SoilRecord(
      imagePath: image.path,
      latitude: _state.latitude,
      longitude: _state.longitude,
      address: _state.address,
      horizontalAccuracy: _state.horizontalAccuracy,
      timestamp: (_resultAt ?? DateTime.now()).toIso8601String(),
      textureClass: result?.textureClass,
      confidenceScore: result?.confidenceScore,
      fieldName: trimmed(labels?.fieldName),
      sampleLabel: trimmed(labels?.sampleLabel),
      classificationFailure: result == null
          ? _state.classificationFailureCause
          : null,
    );
  }

  /// The draft's outlined bookmark, which saves it (SPEC 0196).
  Widget _saveBookmark() => VisioIconButton(
    label: AppStrings.resultSave,
    icon: LucideIcons.bookmark,
    color: context.palette.onSurface,
    onPressed: _state.isSaving ? null : _saveRecord,
  );

  /// The result as it will be saved (PNG 32, SPEC 0202): the saved result's
  /// app bar and footer; the bookmark saves and back discards.
  Widget _draftResult(File image, InferenceResult result) {
    final draft = _draftRecord(image, result);
    return ResultContent(
      key: ValueKey(_state.generation),
      record: draft,
      locating: _state.isLocating,
      announce: true,
      appBar: resultAppBar(
        context,
        bookmark: _saveBookmark(),
        onShare: () => shareRecordWithConsent(context, ref, draft),
      ),
      managementTab: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          AppStrings.resultDraftManagement,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      detailsTab: SizedBox(
        height: 420,
        child: CaptureImagePreview(
          image: image,
          sample: ref.watch(soilSampleProvider(image.path)).value,
          isLoading: _state.isLocating,
          isClassifying: false,
          address: _state.address,
          latitude: _state.latitude,
          longitude: _state.longitude,
          classificationResult: result,
        ),
      ),
      footerBuilder: (context, selectTab) => ResultFooter(
        onCorrect: () => _editDraftLabels(draft),
        onManagementTips: () => selectTab(ResultTab.management),
      ),
    );
  }

  /// A photograph that was not classified, as PNG 15 shows it (SPEC 0202):
  /// why and how to try again; the bookmark still saves it (SPEC 0173).
  Widget _failedResult(File image) {
    final draft = _draftRecord(image, null);
    return ResultContent(
      key: ValueKey(_state.generation),
      record: draft,
      announce: true,
      appBar: resultAppBar(
        context,
        bookmark: _saveBookmark(),
        onShare: () => shareRecordWithConsent(context, ref, draft),
      ),
      errorBlock: ResultErrorBlock(
        cause: _state.classificationFailureCause,
        onRetake: _pickImage,
        onCaptureTips: () => context.push('/capture-guide'),
      ),
      managementTab: const SizedBox.shrink(),
      detailsTab: const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Shows the permission denied screen if the camera was blocked
    final cameraPermission = _state.cameraPermission;
    if (cameraPermission != null &&
        cameraPermission != AppPermissionStatus.granted) {
      return CameraPermissionDeniedView(
        status: cameraPermission,
        onRetry: _retryCameraPermission,
      );
    }

    final selectedImage = ref.watch(imageProvider);
    final image = selectedImage.file;
    final hasImage = selectedImage.hasImage;

    // A classified photograph is shown as the result it will be once saved
    // (SPEC 0196); a failure keeps the preview with its cause and retry.
    final result = _state.classificationResult;
    if (image != null && result != null && !_state.isClassifying) {
      return PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _discardOnLeave();
        },
        child: _draftResult(image, result),
      );
    }

    // A failure reads as the v11 error result (SPEC 0197): why, how to try
    // again, and the photograph, which can still be saved (SPEC 0173).
    if (image != null && _state.classificationFailed && !_state.isClassifying) {
      return PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _discardOnLeave();
        },
        child: _failedResult(image),
      );
    }

    // A save replaces this route instead of popping it (SPEC 0132), so only
    // back runs this.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discardOnLeave();
      },
      child: Scaffold(
        appBar: VisioAppBar(
          title: _state.isClassifying ? 'Resultado' : 'Nova captura',
          centerTitle: !_state.isClassifying,
          leading: _state.isClassifying
              ? VisioIconButton(
                  label: 'Descartar',
                  icon: Icons.arrow_back,
                  onPressed: _discardImage,
                )
              : null,
          actions: _state.isClassifying
              ? []
              : [
                  // The protocol on demand; it returns here and opens no camera
                  // (SPEC 0142).
                  VisioIconButton(
                    label: 'Como capturar',
                    icon: Icons.help_outline,
                    onPressed: () => context.push('/capture-guide'),
                  ),
                ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _state.isClassifying
                      ? ProcessingView(
                          key: ValueKey(_state.generation),
                          highlightClass: _processingClass,
                          phaseLabel: switch (_state.classificationPhase) {
                            null => 'Classificando...',
                            ClassificationPhase.readingPhotograph =>
                              'Lendo a foto...',
                            ClassificationPhase.findingSheet =>
                              'Procurando a folha A4...',
                            ClassificationPhase.describingTexture =>
                              'Descrevendo a textura...',
                            ClassificationPhase.scoring =>
                              'Calculando a classe...',
                          },
                          onSettled: () {
                            final settlement = _settlement;
                            if (settlement != null && !settlement.isCompleted) {
                              settlement.complete();
                            }
                          },
                        )
                      : CaptureImagePreview(
                          image: image,
                          // Cut once the classification is done, so the two do not
                          // compete for the phone (SPEC 0172).
                          sample: image == null || _state.isClassifying
                              ? null
                              : ref.watch(soilSampleProvider(image.path)).value,
                          isLoading: _state.isLocating,
                          isClassifying: _state.isClassifying,
                          classificationPhase: _state.classificationPhase,
                          address: _state.address,
                          latitude: _state.latitude,
                          longitude: _state.longitude,
                          classificationResult: _state.classificationResult,
                          classificationFailed: _state.classificationFailed,
                          classificationFailureCause:
                              _state.classificationFailureCause,
                          onRetryClassification: _retryClassification,
                        ),
                ),
                if (!_state.isClassifying) ...[
                  const SizedBox(height: AppSpacing.lg),
                  CaptureActions(
                    hasImage: hasImage,
                    // Location is optional, so Save does not wait for it; a record
                    // saved first has no coordinates (SPEC 0117).
                    isBusy: _state.isClassifying || _state.isSaving,
                    onCapture: _pickImage,
                    onSave: _saveRecord,
                    onRetake: _pickImage,
                    onDiscard: _discardImage,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
