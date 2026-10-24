import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: StatsRow(
        cells: [
          StatCell(
            value: stats != null ? '${stats.totalRecords}' : '-',
            label: 'Análises',
            icon: Icons.layers,
            color: context.palette.primary,
          ),
          StatCell(
            value: stats != null ? '${stats.distinctLocations}' : '-',
            label: 'Locais',
            icon: Icons.map_outlined,
            color: context.palette.secondary,
          ),
          StatCell(
            value: stats?.formattedConfidence ?? '-',
            label: 'Confiança',
            icon: Icons.track_changes,
            color: context.palette.tertiary,
          ),
        ],
      ),
    );
  }
}
