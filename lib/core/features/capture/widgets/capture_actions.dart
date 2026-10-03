import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/widgets/camera_rationale.dart';
import 'package:visiosoil_app/core/features/capture/widgets/location_rationale.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// The capture screen's primary action row: a single "Câmera" button before a
/// photo exists, and Save/Discard once one does. [isBusy] disables Save while
/// classification is still running or a save is in flight; location does not
/// hold it (SPEC 0117). Before
/// a photo exists, a [CameraRationale] and a [LocationRationale] line explain
/// the requests the capture will make, in the order it makes them.
class CaptureActions extends StatelessWidget {
  const CaptureActions({
    super.key,
    required this.hasImage,
    required this.isBusy,
    required this.onCapture,
    required this.onSave,
    required this.onDiscard,
    this.checkCameraPermission,
    this.checkLocationPermission,
  });

  final bool hasImage;
  final bool isBusy;
  final VoidCallback onCapture;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  /// Passed to the [CameraRationale]; defaults to the platform's status.
  final Future<AppPermissionStatus> Function()? checkCameraPermission;

  /// Passed to the [LocationRationale]; defaults to the platform's status.
  final Future<AppPermissionStatus> Function()? checkLocationPermission;

  @override
  Widget build(BuildContext context) {
    if (!hasImage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          VisioButton(
            label: 'Câmera',
            icon: Icons.camera_alt,
            onPressed: onCapture,
            expanded: true,
          ),
          CameraRationale(checkPermission: checkCameraPermission),
          LocationRationale(checkPermission: checkLocationPermission),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisioButton(
          label: 'Salvar registro',
          icon: Icons.check,
          onPressed: isBusy ? null : onSave,
          isLoading: isBusy,
          expanded: true,
        ),
        // Discard keeps 24 dp from Save against a mis-tap (SPEC 0118).
        const SizedBox(height: AppSpacing.xl),
        VisioButton(
          label: 'Descartar',
          icon: Icons.close,
          onPressed: onDiscard,
          variant: VisioButtonVariant.secondary,
          expanded: true,
        ),
      ],
    );
  }
}
