import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// What the result screen shows for a record saved without a classification
/// (redesign v11 §3.6 PNG 15, SPEC 0194): why, in the capture chip's words
/// (SPEC 0173), and the two ways forward; nothing else, as PNG 15 shows it
/// (SPEC 0202).
class ResultErrorBlock extends StatelessWidget {
  const ResultErrorBlock({
    super.key,
    required this.cause,
    this.onRetake,
    this.onCaptureTips,
  });

  /// Null for a record saved before the cause was kept.
  final ClassificationFailureCause? cause;

  /// What "Fotografar de novo" and "Ver dicas de captura" do; by default
  /// they open capture and the capture guide. Capture passes its own retake
  /// and guide (SPEC 0197).
  final VoidCallback? onRetake;
  final VoidCallback? onCaptureTips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final failure = cause;

    // Centred, as PNG 15 measures it (SPEC 0202): a 56 dp disc, the 18 sp
    // title 16 dp below, the 14/20 cause, then the label-wide primary and
    // the text link.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.circleAlert,
              color: palette.onErrorContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.resultErrorTitle,
            textAlign: TextAlign.center,
            style: AppTypography.resized(theme.textTheme.titleMedium!, 18),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            failure == null
                ? AppStrings.resultErrorWithoutCause
                : classificationFailureReason(failure),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          VisioButton(
            label: AppStrings.resultRetake,
            icon: LucideIcons.camera,
            onPressed: onRetake ?? () => context.push('/capture'),
          ),
          const SizedBox(height: AppSpacing.sm),
          VisioButton(
            label: AppStrings.resultCaptureTips,
            variant: VisioButtonVariant.text,
            onPressed: onCaptureTips ?? () => context.push('/capture-guide'),
          ),
        ],
      ),
    );
  }
}
