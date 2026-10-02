import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// One line, shown before a capture while the camera is not granted, saying why
/// the capture will ask for it (SPEC 0115). Android's camera dialog carries no
/// word from the app; iOS already shows `NSCameraUsageDescription`. Mirrors
/// `LocationRationale` (SPEC 0099).
class CameraRationale extends StatefulWidget {
  const CameraRationale({super.key, this.checkPermission});

  static const String message =
      'A câmera fotografa a amostra sobre a folha A4 para classificar a textura '
      'do solo.';

  /// Reads the camera permission; defaults to [PermissionService.checkCamera].
  /// Injected so tests can answer without the platform plugin.
  final Future<AppPermissionStatus> Function()? checkPermission;

  @override
  State<CameraRationale> createState() => _CameraRationaleState();
}

class _CameraRationaleState extends State<CameraRationale> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final check = widget.checkPermission ?? PermissionService.checkCamera;
    final AppPermissionStatus status;
    try {
      status = await check();
    } catch (_) {
      // An unreadable status shows nothing rather than a claim the app cannot
      // back.
      return;
    }
    if (!mounted || status == AppPermissionStatus.granted) return;
    setState(() => _show = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        CameraRationale.message,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.palette.onSurfaceVariant),
      ),
    );
  }
}
