import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

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
  static const double _chipGap = 9;

  /// PNG 13 and 38 wrap the sentence and the disclaimer 39 dp from the
  /// screen's edges: the capture screen's 16 dp, this view's 4 dp, then this.
  static const double _textInset = 19;
  static const double _triangleShare = (246 - 21.5) / 246;

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
          // PNG 13 sets the triangle 12.5 dp higher than the 32 dp gap did
          // (SPEC 0211).
          const SizedBox(height: 19.5),
          // The triangle's box keeps room under its labels that PNG 13 does
          // not: the chip sits 21.5 dp higher on a 300 dp triangle.
          Align(
            alignment: Alignment.topCenter,
            heightFactor: _triangleShare,
            child: TextureTriangle(
              highlightClass: widget.highlightClass,
              mode: TextureTriangleMode.processing,
              onSettled: _onSettled,
            ),
          ),
          const SizedBox(height: _chipGap),
          // 24 dp, plus Modo Sol's 2 dp rule above and below (PNG 38). A
          // minimum rather than a height, so enlarged text grows the chip.
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  24 + (palette.isSun ? 2 * context.density.borderWidth : 0),
            ),
            child: _settled && widget.highlightClass != null
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: palette.selected,
                        borderRadius: BorderRadius.circular(6),
                        border: palette.isSun
                            ? Border.all(
                                color: palette.outline,
                                width: context.density.borderWidth,
                              )
                            : null,
                      ),
                      // PNG 38 sets the class larger and in ink in Modo Sol.
                      child: Text(
                        widget.highlightClass!,
                        style:
                            AppTypography.resized(
                              text.labelMedium!,
                              palette.isSun ? 14 : 12,
                              height: 16 / (palette.isSun ? 14 : 12),
                            ).copyWith(
                              color: palette.isSun
                                  ? palette.onSurface
                                  : palette.primaryText,
                              letterSpacing: 0,
                            ),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 15),
          Text(
            AppStrings.processingTitle,
            textAlign: TextAlign.center,
            style: AppTypography.resized(
              text.titleLarge!,
              20,
              height: 24 / 20,
            ).copyWith(letterSpacing: 0),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _textInset),
            child: Text(
              '${AppStrings.processingModel} · ${AppStrings.processingEstimate}',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: palette.onSurfaceVariant),
            ),
          ),
          // The phase is read aloud, not drawn: PNG 13 shows no phase line.
          if (widget.phaseLabel != null)
            Semantics(
              liveRegion: true,
              label: widget.phaseLabel,
              child: const SizedBox.shrink(),
            ),
          const SizedBox(height: AppSpacing.sm),
          // 12/16 in every theme, Modo Sol included (PNG 38).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _textInset),
            child: Text(
              AppStrings.textureDiagramDisclaimer,
              textAlign: TextAlign.center,
              style: AppTypography.resized(
                text.bodySmall!,
                12,
                height: 16 / 12,
              ).copyWith(color: palette.textTertiary),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
