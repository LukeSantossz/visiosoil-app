import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/soil_texture_reference.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/empty_state.dart';
import 'package:visiosoil_app/core/widgets/offline_banner.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/swipe_to_delete.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Date-grouped history. Deferred deletes preserve the repository's original
/// record identity, photograph, and timestamp throughout the undo window.
class HistoryList extends ConsumerStatefulWidget {
  const HistoryList({
    super.key,
    required this.pageSize,
    required this.selectedIds,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onSelect,
    this.activeId,
  });
  final int pageSize;
  final Set<int> selectedIds;
  final bool isSelectionMode;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  /// A row's "Selecionar" semantics action (SPEC 0203).
  final ValueChanged<int>? onSelect;

  /// The record open beside the list in master-detail (SPEC 0200).
  final int? activeId;

  @override
  ConsumerState<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends ConsumerState<HistoryList> {
  late int _shown = widget.pageSize;
  final Set<int> _hidden = {};
  bool _collection = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(filteredRecordsProvider);
    final all =
        ref.watch(soilRecordsStreamProvider).asData?.value ??
        const <SoilRecord>[];
    final offline =
        ref.watch(connectivityStatusProvider).asData?.value ==
        ConnectivityStatus.offline;
    final records = all.where((r) => !_hidden.contains(r.id)).toList();
    final pending = records.where((r) => r.syncStatus == 'pending').length;
    return CustomScrollView(
      slivers: [
        // Directly under the app bar at 16 dp margins; its hit area reaches
        // 8 dp below the pill, into the gap above the summary (PNG 16,
        // SPEC 0203).
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(
            // The width the list has, not the screen's: beside a detail pane
            // the list is narrower than the screen (SPEC 0200). At any text
            // size it stays within it, its labels shrinking to fit their
            // segment (SPEC 0197, SPEC 0222).
            child: SegmentedControl<bool>(
              options: const [
                SegmentedControlOption(
                  value: false,
                  label: 'Análises',
                  icon: LucideIcons.history,
                ),
                SegmentedControlOption(
                  value: true,
                  label: 'Coleção',
                  icon: LucideIcons.layers,
                ),
              ],
              value: _collection,
              onChanged: (value) => setState(() => _collection = value),
            ),
          ),
        ),
        if (offline)
          SliverToBoxAdapter(child: OfflineBanner(pendingCount: pending)),
        ...data.when(
          skipError: false,
          skipLoadingOnRefresh: false,
          loading: () => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text('Carregando histórico'),
                  ),
                  AnalysisTileSkeleton(),
                  AnalysisTileSkeleton(),
                  AnalysisTileSkeleton(),
                ],
              ),
            ),
          ],
          error: (error, stack) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Não foi possível carregar o histórico.',
                action: VisioButton(
                  label: 'Tentar de novo',
                  variant: VisioButtonVariant.secondary,
                  onPressed: () => ref.invalidate(filteredRecordsProvider),
                ),
              ),
            ),
          ],
          data: (filtered) {
            final visible = filtered
                .where((r) => !_hidden.contains(r.id))
                .toList();
            if (_collection) {
              return [
                SliverPadding(
                  padding: const EdgeInsets.all(
                    (AppSpacing.lg + AppSpacing.xs),
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Collection(
                      records: records,
                      classes: ref.watch(contractClassesProvider).value,
                    ),
                  ),
                ),
              ];
            }
            if (visible.isEmpty) {
              final hasFilter =
                  ref.watch(selectedTextureFilterProvider) != null ||
                  ref.watch(searchTermProvider).isNotEmpty;
              if (!hasFilter) {
                return [const SliverToBoxAdapter(child: _NoRecords())];
              }
              return [
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: 'Nenhum resultado',
                    description:
                        'Tente ajustar os filtros ou o termo de busca.',
                  ),
                ),
              ];
            }
            final shown = visible.take(_shown).toList();
            return [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverToBoxAdapter(
                  child: _Summary(
                    records: records,
                    classes: ref.watch(contractClassesProvider).value,
                  ),
                ),
              ),
              if (visible.length > _shown)
                SliverToBoxAdapter(
                  child: Text(
                    'Mostrando os $_shown registros mais recentes de ${visible.length}.',
                    textAlign: TextAlign.center,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                sliver: SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final record = shown[index];
                    final heading = _dateHeading(record.timestamp);
                    return Column(
                      key: ValueKey<int>(record.id!),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (index == 0 ||
                            heading != _dateHeading(shown[index - 1].timestamp))
                          // 14 sp in onSurfaceVariant over a rule (PNG 16).
                          Container(
                            padding: const EdgeInsets.only(
                              top: AppSpacing.xl,
                              bottom: AppSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: context.palette.divider,
                                  width: context.palette.edgeWidth,
                                ),
                              ),
                            ),
                            child: Semantics(
                              header: true,
                              child: Text(
                                heading,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: context.palette.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        _row(record),
                        Divider(height: 1, color: context.palette.divider),
                      ],
                    );
                  },
                ),
              ),
              if (visible.length > _shown)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(
                      (AppSpacing.lg + AppSpacing.xs),
                    ),
                    child: VisioButton(
                      label: 'Mostrar mais registros',
                      variant: VisioButtonVariant.secondary,
                      onPressed: () =>
                          setState(() => _shown += widget.pageSize),
                    ),
                  ),
                ),
            ];
          },
        ),
      ],
    );
  }

  Widget _row(SoilRecord record) {
    final id = record.id!;
    final tile = Semantics(
      selected: widget.isSelectionMode
          ? widget.selectedIds.contains(id)
          : (id == widget.activeId ? true : null),
      container: true,
      child: ColoredBox(
        color:
            (widget.isSelectionMode
                ? widget.selectedIds.contains(id)
                : id == widget.activeId)
            ? context.palette.selected
            : context.palette.background,
        child: AnalysisTile(
          record: record,
          history: true,
          onLongPress: () => widget.onLongPress(id),
          onSelect: widget.isSelectionMode || widget.onSelect == null
              ? null
              : () => widget.onSelect!(id),
          onTap: () => widget.onTap(id),
        ),
      ),
    );
    if (widget.isSelectionMode) return tile;
    // Capture dependencies now: snackbar completion can outlive this list.
    late SoilRecordRepository repository;
    final messenger = ScaffoldMessenger.of(context);
    return SwipeToDelete(
      key: ValueKey('swipe-$id'),
      onDelete: () {
        repository = ref.read(soilRecordRepositoryProvider);
        setState(() => _hidden.add(id));
      },
      onUndo: () {
        if (mounted) setState(() => _hidden.remove(id));
      },
      onSnackbarClosed: (reason) async {
        if (reason == SnackBarClosedReason.action) return;
        try {
          await repository.deleteById(id);
        } catch (_) {
          // Persistence is a boundary: leave the record accessible on failure.
          if (mounted) setState(() => _hidden.remove(id));
          if (messenger.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Não foi possível excluir a análise. Tente de novo.',
                ),
              ),
            );
          }
        }
      },
      child: tile,
    );
  }
}

String _dateHeading(String timestamp) {
  final date = DateTime.tryParse(timestamp)?.toLocal();
  if (date == null) return 'Data não disponível';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Hoje';
  if (day == DateTime(today.year, today.month, today.day - 1)) return 'Ontem';
  const months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez',
  ];
  return '${date.day} ${months[date.month - 1]}${date.year == now.year ? '' : ' ${date.year}'}';
}

class _Summary extends StatelessWidget {
  const _Summary({required this.records, required this.classes});
  final List<SoilRecord> records;

  /// The contract's classes, null while unknown (SPEC 0223).
  final List<String>? classes;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final week = records.where((r) {
      final date = DateTime.tryParse(r.timestamp)?.toLocal();
      return date != null && !date.isBefore(monday) && !date.isAfter(now);
    }).length;
    final total = classes;
    final earned = total == null
        ? null
        : records
              .where((r) => r.hasClassification)
              .map((r) => r.textureClass)
              .toSet()
              .intersection(total.toSet())
              .length;
    final cells = [
      ('${records.length}', 'análises', null),
      (
        '$week',
        'nesta semana',
        '${Formatters.count(week, 'análise', 'análises')} nesta semana',
      ),
      (
        earned == null ? '—' : '$earned/${total!.length}',
        'classes',
        earned == null
            ? null
            : '$earned de ${total!.length} classes na coleção',
      ),
    ];
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final rule = BorderSide(
      color: context.palette.divider,
      width: context.palette.edgeWidth,
    );
    // One bordered strip split in three (PNG 16, SPEC 0203); a column of
    // cells from 1.3x text.
    return Container(
      key: const Key('history-summary'),
      decoration: BoxDecoration(
        border: Border.fromBorderSide(rule),
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: IntrinsicHeight(
        child: Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++)
              Flexible(
                fit: FlexFit.tight,
                flex: stacked ? 0 : 1,
                child: Container(
                  decoration: i == 0
                      ? null
                      : BoxDecoration(
                          border: stacked
                              ? Border(top: rule)
                              : Border(left: rule),
                        ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _SummaryCell(
                    value: cells[i].$1,
                    label: cells[i].$2,
                    semanticLabel: cells[i].$3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.value,
    required this.label,
    this.semanticLabel,
  });

  final String value;
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The value 20 sp weight 600, the label 12 sp in textTertiary.
    return Semantics(
      label: semanticLabel ?? '$value $label',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTypography.tabular(
                theme.textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The contract's classes as tiles, in its order (SPEC 0223).
class _Collection extends StatelessWidget {
  const _Collection({required this.records, required this.classes});
  final List<SoilRecord> records;

  /// Null while unknown, when the grid holds no tile.
  final List<String>? classes;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final name in classes ?? const <String>[])
          Builder(
            builder: (context) {
              final earned = records.any((r) => r.textureClass == name);
              return Semantics(
                label:
                    '${SoilTextureReference.labelFor(name)}, '
                    '${earned ? 'conquistada' : 'não conquistada'}',
                child: ExcludeSemantics(
                  child: Container(
                    width: (constraints.maxWidth - AppSpacing.sm) / 2,
                    constraints: BoxConstraints(minHeight: context.density.tap),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: earned
                          ? SoilTextureColors.forClass(
                              name,
                            ).withValues(alpha: .15)
                          : context.palette.background,
                      borderRadius: AppRadius.borderRadiusMd,
                      border: Border.all(
                        color: context.palette.outline,
                        width: context.density.borderWidth,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          earned
                              ? Icons.check_circle_outline
                              : Icons.circle_outlined,
                          color: earned
                              ? context.palette.primaryText
                              : context.palette.onSurfaceVariant,
                        ),
                        Text(
                          SoilTextureReference.labelFor(name),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}

/// PNG 17: the empty history, its drawing 74.5 dp under the segmented
/// control, an 18 sp title, the 14/20 sentence and the action (SPEC 0210).
class _NoRecords extends StatelessWidget {
  const _NoRecords();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        _NoRecords.top,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        children: [
          ExcludeSemantics(
            child: CustomPaint(
              size: const Size(100, 77),
              painter: _NoRecordsArt(
                ink: palette.primaryText,
                fill: palette.primaryContainer.withValues(alpha: .55),
                line: palette.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 31),
          Semantics(
            header: true,
            child: Text(
              'Nenhuma análise ainda',
              textAlign: TextAlign.center,
              style: AppTypography.weighted(
                AppTypography.resized(
                  theme.textTheme.titleMedium!,
                  18,
                  height: 24 / 18,
                ),
                600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Suas análises aparecem aqui, agrupadas por data, mesmo sem '
            'internet.',
            textAlign: TextAlign.center,
            style: AppTypography.resized(
              theme.textTheme.bodyMedium!,
              14,
              height: 20 / 14,
            ).copyWith(color: palette.onSurfaceVariant),
          ),
          const SizedBox(height: 21),
          VisioButton(
            label: 'Fazer primeira análise',
            icon: LucideIcons.camera,
            onPressed: () => context.push('/capture'),
          ),
        ],
      ),
    );
  }

  /// From the list's top to the drawing's.
  static const double top = 74.5;
}

/// Two record cards behind a dashed one holding a sample and two lines, at
/// PNG 17's coordinates (SPEC 0210).
class _NoRecordsArt extends CustomPainter {
  const _NoRecordsArt({
    required this.ink,
    required this.fill,
    required this.line,
  });

  final Color ink;
  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final front = RRect.fromLTRBR(
      3.25,
      29.75,
      96.5,
      75.5,
      const Radius.circular(9),
    );
    canvas.drawRRect(front, Paint()..color = fill);
    canvas.drawRRect(
      RRect.fromLTRBR(16, 1, 84, 22.25, const Radius.circular(6)),
      stroke(line.withValues(alpha: .45), 1.5),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(9.75, 13.5, 90.25, 38, const Radius.circular(6)),
      stroke(line.withValues(alpha: .75), 1.5),
    );
    final dash = stroke(ink, 1.5)..strokeCap = StrokeCap.butt;
    for (final metric in (Path()..addRRect(front)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9.5) {
        canvas.drawPath(metric.extractPath(d, d + 6), dash);
      }
    }
    canvas.drawRRect(
      RRect.fromLTRBR(12.75, 39, 39, 65.25, const Radius.circular(6)),
      stroke(ink, 1.5),
    );
    for (final (center, radius) in const [
      (Offset(26, 52.25), 2.75),
      (Offset(21, 57.25), 1.5),
      (Offset(30.75, 58.5), 1.9),
    ]) {
      canvas.drawCircle(center, radius, Paint()..color = ink);
    }
    canvas.drawLine(
      const Offset(46.25, 47.5),
      const Offset(82.5, 47.5),
      stroke(line, 1.25),
    );
    canvas.drawLine(
      const Offset(46.25, 57.25),
      const Offset(69.75, 57.25),
      stroke(line, 1.25),
    );
  }

  @override
  bool shouldRepaint(_NoRecordsArt oldDelegate) =>
      ink != oldDelegate.ink ||
      fill != oldDelegate.fill ||
      line != oldDelegate.line;
}
