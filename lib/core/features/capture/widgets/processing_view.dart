import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// The local classifier's waiting surface; no sample fractions are implied.
class ProcessingView extends StatefulWidget {
  const ProcessingView({
    super.key,
    this.highlightClass,
    this.onSettled,
    this.phaseLabel,
  });
  final String? highlightClass;
  final VoidCallback? onSettled;
  final String? phaseLabel;

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView> {
  bool _settled = false;

  @override
  void didUpdateWidget(ProcessingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightClass != oldWidget.highlightClass) _settled = false;
  }

  void _onSettled() {
    setState(() => _settled = true);
    widget.onSettled?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),
          TextureTriangle(
            highlightClass: widget.highlightClass,
            mode: TextureTriangleMode.processing,
            onSettled: _onSettled,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_settled && widget.highlightClass != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: palette.selected,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: palette.isSun
                    ? Border.all(
                        color: palette.outline,
                        width: context.density.borderWidth,
                      )
                    : null,
              ),
              child: Text(
                widget.highlightClass!,
                style: text.titleMedium?.copyWith(color: palette.primaryText),
              ),
            )
          else
            const SizedBox(height: AppSpacing.xxl),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.processingTitle,
            textAlign: TextAlign.center,
            style: text.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${AppStrings.processingModel} · ${AppStrings.processingEstimate}',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: palette.onSurfaceVariant),
          ),
          if (widget.phaseLabel != null)
            Semantics(
              liveRegion: true,
              child: Text(
                widget.phaseLabel!,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          // Static progress keeps the waiting state readable without tickers.
          TickerMode(
            enabled:
                !palette.isSun &&
                !AppMotion.reduceMotion &&
                !MediaQuery.disableAnimationsOf(context),
            child: LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: AppStrings.processingTitle,
              color: palette.primary,
              backgroundColor: palette.divider,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.textureDiagramDisclaimer,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: palette.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
