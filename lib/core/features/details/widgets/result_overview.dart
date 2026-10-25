import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/constants/soil_texture_reference.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The result's "Visão geral" tab (redesign v11 §3.6, SPEC 0194): what the
/// result means, reference text for the class, where the sample came from,
/// and the laboratory notice.
class ResultOverview extends StatelessWidget {
  const ResultOverview({super.key, required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final about = SoilTextureReference.forClass(record.textureClass);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStrings.resultIntro, style: theme.textTheme.bodyMedium),
        // Static text for the class, not model output (redesign v11 §11).
        if (about != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _ResultCard(
            title: AppStrings.resultAboutClassTitle,
            caption: AppStrings.resultAboutClassCaption,
            body: about,
            note: AppStrings.resultAboutClassNote,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _ResultCard(
          title: AppStrings.resultSampleTitle,
          body: _sampleLine(record),
        ),
        const SizedBox(height: AppSpacing.md),
        _LabNotice(),
      ],
    );
  }

  /// Where the sample was taken, then the labels the agronomist gave it.
  static String _sampleLine(SoilRecord record) {
    final location = [
      if (record.hasValidAddress) record.displayAddress,
      if (record.hasCoordinates) record.formattedCoordinates,
    ];
    return [
      if (location.isEmpty) AppStrings.resultSampleUnlocated else ...location,
      if (record.hasLabels) record.labelsSummary,
    ].join(' · ');
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.body,
    this.caption,
    this.note,
  });

  final String title;
  final String body;
  final String? caption;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: context.palette.onSurfaceVariant,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.borderRadiusLg,
        border: Border.all(
          color: context.palette.cardBorder,
          width: context.palette.edgeWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (caption != null) Text(caption!, style: secondary),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: theme.textTheme.bodyMedium),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(note!, style: secondary),
          ],
        ],
      ),
    );
  }
}

class _LabNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = context.palette.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            AppStrings.resultLabNotice,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
