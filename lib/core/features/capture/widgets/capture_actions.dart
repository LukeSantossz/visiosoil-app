import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// The capture screen's primary action row: a single "Câmera" button before a
/// photo exists, and Save/Discard once one does. [isBusy] disables Save while
/// location or classification is still running or a save is in flight.
class CaptureActions extends StatelessWidget {
  const CaptureActions({
    super.key,
    required this.hasImage,
    required this.isBusy,
    required this.onCapture,
    required this.onSave,
    required this.onDiscard,
  });

  final bool hasImage;
  final bool isBusy;
  final VoidCallback onCapture;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    if (!hasImage) {
      return VisioButton(
        label: 'Câmera',
        icon: Icons.camera_alt,
        onPressed: onCapture,
        expanded: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisioButton(
          label: 'Salvar Registro',
          icon: Icons.check,
          onPressed: isBusy ? null : onSave,
          isLoading: isBusy,
          expanded: true,
        ),
        const SizedBox(height: AppSpacing.sm),
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
