import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
      child: OutlinedButton(
        onPressed: onCapture,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          // 56 dp in every theme, Modo Sol's target included (PNG 08, 25).
          minimumSize: const Size(0, 56),
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 69, 0),
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
        // A 20 dp scan icon 20 dp in, the 17 sp text 16 dp after it, and the
        // image icon 69 dp from the end, where PNG 08 draws it (SPEC 0203).
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                LucideIcons.scan,
                size: 20,
                color: context.palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                'Analisar solo',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.palette.onSurfaceVariant,
                  fontSize: 17,
                  height: 24 / 17,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ExcludeSemantics(
              child: Icon(
                LucideIcons.image,
                size: 20,
                color: context.palette.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
