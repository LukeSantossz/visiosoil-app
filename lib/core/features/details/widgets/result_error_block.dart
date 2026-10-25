import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// What the result screen shows for a record saved without a classification
/// (redesign v11 §3.6 PNG 15, SPEC 0194): why, in the capture chip's words
/// (SPEC 0173), and the two ways forward.
class ResultErrorBlock extends StatelessWidget {
  const ResultErrorBlock({super.key, required this.cause});

  /// Null for a record saved before the cause was kept.
  final ClassificationFailureCause? cause;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final failure = cause;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, color: palette.onErrorContainer),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.resultErrorTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          failure == null
              ? AppStrings.resultErrorWithoutCause
              : classificationFailureChip(failure).label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        VisioButton(
          label: AppStrings.resultRetake,
          icon: Icons.photo_camera_outlined,
          onPressed: () => context.push('/capture'),
        ),
        const SizedBox(height: AppSpacing.sm),
        VisioButton(
          label: AppStrings.resultCaptureTips,
          variant: VisioButtonVariant.text,
          onPressed: () => context.push('/capture-guide'),
        ),
      ],
    );
  }
}
