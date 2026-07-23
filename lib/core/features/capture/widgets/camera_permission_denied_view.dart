import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/widgets/permission_denied_view.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';

/// The capture screen shown when camera access is denied or restricted: the app
/// bar plus a [PermissionDeniedView] whose copy and retry affordance depend on
/// [status]. A restricted status (iOS parental/MDM) cannot be changed by the
/// user, so it offers no retry.
class CameraPermissionDeniedView extends StatelessWidget {
  const CameraPermissionDeniedView({
    super.key,
    required this.status,
    required this.onRetry,
  });

  final AppPermissionStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isRestricted = status == AppPermissionStatus.restricted;
    final isPermanentlyDenied = status == AppPermissionStatus.permanentlyDenied;

    return Scaffold(
      appBar: const VisioAppBar(title: 'Nova Captura'),
      body: PermissionDeniedView(
        icon: Icons.camera_alt,
        title: isRestricted ? 'Camera restrita' : 'Acesso a camera necessario',
        description: isRestricted
            ? 'O acesso a camera esta restrito por configuracoes do dispositivo (controle parental ou MDM). Contacte o administrador.'
            : 'Para capturar fotos de amostras de solo, o VisioSoil precisa de acesso a camera do dispositivo.',
        isPermanentlyDenied: isPermanentlyDenied || isRestricted,
        onRetry: isRestricted ? null : onRetry,
      ),
    );
  }
}
