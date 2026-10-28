import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Weekly activity, observed collection and confidence of the latest capture.
class StatsGrid extends StatelessWidget {
  const StatsGrid({
    super.key,
    required this.recordsAsync,
    this.collectionClasses,
  });
  final AsyncValue<List<SoilRecord>> recordsAsync;

  /// The contract's classes the collection counts, null while unknown
  /// (SPEC 0223).
  final List<String>? collectionClasses;

  @override
  Widget build(BuildContext context) {
    final records = recordsAsync.value ?? <SoilRecord>[];
    final loading = recordsAsync.isLoading;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekly = records.where((record) {
      final date = DateTime.tryParse(record.timestamp)?.toLocal();
      return date != null && !date.isBefore(monday) && !date.isAfter(now);
    }).length;
    // The contract's classes the records hold, counted as Perfil and the
    // history count them (SPEC 0223).
    final total = collectionClasses;
    final classes = total == null
        ? null
        : records
              .where((r) => r.hasClassification)
              .map((r) => r.textureClass)
              .toSet()
              .intersection(total.toSet())
              .length;
    final score = records.isNotEmpty ? records.first.confidenceScore : null;
    final cells = loading
        ? List.generate(3, (_) => const StatCell.skeleton())
        : [
            StatCell(
              value: '$weekly',
              label: 'análises',
              icon: LucideIcons.scan,
              semanticLabel:
                  '${Formatters.count(weekly, 'análise', 'análises')} '
                  'nesta semana',
            ),
            StatCell(
              value: classes == null ? '—' : '$classes/${total!.length}',
              label: 'coleção',
              icon: LucideIcons.layers,
              semanticLabel: classes == null
                  ? null
                  : '$classes de ${total!.length} classes na coleção',
            ),
            StatCell(
              value: score != null && score.isFinite
                  ? '${floorConfidencePercent(score)}%'
                  : '—',
              label: records.isEmpty ? 'última classe' : 'última confiança',
              icon: LucideIcons.sprout,
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
    // The cards take the tallest one's content: 104 dp in PNG 09, and 120 dp
    // in PNG 08, where "última confiança" wraps (SPEC 0216). The skeleton holds
    // the empty height, so "Recentes" does not move when the data arrives.
    return StatsRow(cells: cells, minHeight: loading ? 104 : 0);
  }
}
