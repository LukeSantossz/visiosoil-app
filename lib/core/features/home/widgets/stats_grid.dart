import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Weekly activity, observed collection and confidence of the latest capture.
class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.recordsAsync});
  final AsyncValue<List<SoilRecord>> recordsAsync;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valueStyle = textTheme.headlineMedium?.copyWith(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
    );
    final labelStyle = textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: context.palette.onSurfaceVariant,
    );
    final records = recordsAsync.value ?? <SoilRecord>[];
    final loading = recordsAsync.isLoading;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekly = records.where((record) {
      final date = DateTime.tryParse(record.timestamp)?.toLocal();
      return date != null && !date.isBefore(monday) && !date.isAfter(now);
    }).length;
    final classes = records
        .where((r) => r.hasClassification)
        .map((r) => r.textureClass)
        .toSet()
        .length;
    final score = records.isNotEmpty ? records.first.confidenceScore : null;
    final cells = loading
        ? List.generate(3, (_) => const StatCell.skeleton())
        : [
            StatCell(
              valueStyle: valueStyle,
              labelStyle: labelStyle,
              value: '$weekly',
              label: 'análises',
              icon: Icons.crop_free,
              semanticLabel: '$weekly análises nesta semana',
            ),
            StatCell(
              valueStyle: valueStyle,
              labelStyle: labelStyle,
              value: '$classes',
              label: 'coleção',
              icon: Icons.layers_outlined,
              semanticLabel: '$classes classes na coleção',
            ),
            StatCell(
              valueStyle: valueStyle,
              labelStyle: labelStyle,
              value: score != null && score.isFinite
                  ? '${floorConfidencePercent(score)}%'
                  : '—',
              label: records.isEmpty ? 'última classe' : 'última confiança',
              icon: Icons.spa_outlined,
            ),
          ];
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cell in cells)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: cell,
            ),
        ],
      );
    }
    return StatsRow(cells: cells);
  }
}
