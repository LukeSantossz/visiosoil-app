import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/constants/soil_texture_reference.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The result's "Visão geral" tab (redesign v11 §3.6, SPEC 0194): what the
/// result means, reference text for the class, where the sample came from,
/// and the laboratory notice.
class ResultOverview extends StatelessWidget {
  const ResultOverview({
    super.key,
    required this.record,
    this.locating = false,
  });

  final SoilRecord record;

  /// The location is still being read: capture's draft, before a save
  /// (SPEC 0196).
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final about = SoilTextureReference.forClass(record.textureClass);

    final body = theme.textTheme.bodyMedium?.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    final note = theme.textTheme.bodySmall?.copyWith(
      color: context.palette.textTertiary,
    );
    // The class's region, never the sample's position (SPEC 0196): a 150 dp
    // triangle beside its text, as PNG 14 lays it (SPEC 0202).
    final triangle = _ResultSection(
      title: AppStrings.resultTriangleTitle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The triangle's own box keeps room for its labels around it, so
          // it is drawn 205 dp wide and shifted to put its base at 116 dp,
          // 17 dp from the edge, and 3.5 dp up, as PNG 14 and 26 draw it
          // (SPEC 0212).
          SizedBox(
            width: 150,
            height: 146,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 205,
              maxWidth: 205,
              child: Transform.translate(
                offset: const Offset(-27, -3.5),
                child: TextureTriangle(highlightClass: record.textureClass),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 22),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'A região '),
                      TextSpan(
                        text: record.displayTextureClass,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ' está destacada.'),
                    ],
                  ),
                  style: body,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(AppStrings.textureDiagramDisclaimer, style: note),
              ],
            ),
          ),
        ],
      ),
    );
    final information = [
      // Static text for the class, not model output (redesign v11 §11).
      if (about != null) ...[
        _ResultSection(
          title: AppStrings.resultAboutClassTitle,
          caption: AppStrings.resultAboutClassCaption,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(about, style: body),
              const SizedBox(height: AppSpacing.sm),
              Text(AppStrings.resultAboutClassNote, style: note),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      _ResultSection(
        title: AppStrings.resultSampleTitle,
        child: Text(_sampleLine(record, locating: locating), style: body),
      ),
      const SizedBox(height: AppSpacing.xl),
      _LabNotice(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(AppStrings.resultIntro, style: body),
          const SizedBox(height: AppSpacing.xl),
          // Triangle beside the information from 600 dp (redesign v11 §10).
          if (constraints.maxWidth >= 600)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: triangle),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: information,
                  ),
                ),
              ],
            )
          else ...[
            triangle,
            const SizedBox(height: AppSpacing.xl),
            ...information,
          ],
        ],
      ),
    );
  }

  /// Where the sample was taken, then the labels the agronomist gave it.
  static String _sampleLine(SoilRecord record, {required bool locating}) {
    final location = [
      if (record.hasValidAddress) record.displayAddress,
      if (record.hasCoordinates) record.formattedCoordinates,
    ];
    return [
      if (location.isNotEmpty)
        ...location
      else if (locating)
        AppStrings.resultSampleLocating
      else
        AppStrings.resultSampleUnlocated,
      if (record.hasLabels) record.labelsSummary,
    ].join(' · ');
  }
}

/// An open section on the background, titled at 14 sp Inter 600 in
/// `onSurfaceVariant` (PNG 14, SPEC 0202).
class _ResultSection extends StatelessWidget {
  const _ResultSection({
    required this.title,
    required this.child,
    this.caption,
  });

  final String title;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.palette.textTertiary,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
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
        Icon(LucideIcons.info, size: 20, color: color),
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
