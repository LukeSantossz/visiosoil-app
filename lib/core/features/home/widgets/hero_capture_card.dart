import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Compact entry into the existing sheet-guided capture flow.
class HeroCaptureCard extends StatelessWidget {
  const HeroCaptureCard({super.key, required this.onCapture});
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) => Semantics(
    hint: 'Fotografe o solo sobre uma folha A4',
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onCapture,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Analisar solo'),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: Size(0, context.density.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          backgroundColor: context.palette.surface,
          foregroundColor: context.palette.onSurface,
          side: BorderSide(
            color: context.density.borderWidth == 2
                ? context.palette.outline
                : context.palette.surface,
            width: context.density.borderWidth,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusPill,
          ),
        ),
      ),
    ),
  );
}
