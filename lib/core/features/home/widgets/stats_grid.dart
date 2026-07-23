import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/home_stats.dart';

/// The three-up summary row on the home screen: total analyses, distinct
/// locations, and average confidence. Shows `-` until [statsAsync] resolves.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.statsAsync});

  final AsyncValue<HomeStats> statsAsync;

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          _StatCard(
            value: stats != null ? '${stats.totalRecords}' : '-',
            label: 'Analises',
            icon: Icons.layers,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            value: stats != null ? '${stats.distinctLocations}' : '-',
            label: 'Locais',
            icon: Icons.map_outlined,
            color: AppColors.secondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            value: stats?.formattedConfidence ?? '-',
            label: 'Confianca',
            icon: Icons.track_changes,
            color: AppColors.tertiary,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.borderRadiusLg,
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowCard,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
          border:
              Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
