import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The details screen's metadata block: location, collection date, and (when
/// classified) the texture class, each in a bordered info tile.
class InfoSection extends StatelessWidget {
  const InfoSection({super.key, required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoTile(
          icon: Icons.location_on_outlined,
          title: 'Localização',
          value: record.hasValidAddress
              ? record.displayAddress
              : 'Endereço indisponível',
          subtitle:
              record.hasCoordinates ? record.formattedCoordinates : null,
        ),
        const SizedBox(height: AppSpacing.md),
        _InfoTile(
          icon: Icons.calendar_today_outlined,
          title: 'Data da coleta',
          value: record.formattedTimestamp,
        ),
        if (record.hasClassification) ...[
          const SizedBox(height: AppSpacing.md),
          _InfoTile(
            icon: Icons.eco_outlined,
            title: 'Classe textural',
            value: record.displayTextureClass,
            subtitle: 'Confiança: ${record.formattedConfidence}',
          ),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.borderRadiusLg,
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
