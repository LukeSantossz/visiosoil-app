import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/empty_state.dart';
import 'package:visiosoil_app/core/widgets/offline_banner.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/swipe_to_delete.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
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
            // the list is narrower than the screen (SPEC 0200).
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: constraints.maxWidth
                      .clamp(
                        280 * MediaQuery.textScalerOf(context).scale(1),
                        double.infinity,
                      )
                      .toDouble(),
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
                    child: _Collection(records: records),
                  ),
                ),
              ];
            }
            if (visible.isEmpty) {
              final hasFilter =
                  ref.watch(selectedTextureFilterProvider) != null ||
                  ref.watch(searchTermProvider).isNotEmpty;
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: hasFilter
                        ? Icons.search_off
                        : Icons.inventory_2_outlined,
                    title: hasFilter
                        ? 'Nenhum resultado'
                        : 'Nenhuma análise ainda',
                    description: hasFilter
                        ? 'Tente ajustar os filtros ou o termo de busca.'
                        : 'Suas análises aparecem aqui, agrupadas por data, mesmo sem internet.',
                    action: hasFilter
                        ? null
                        : VisioButton(
                            label: 'Fazer primeira análise',
                            icon: Icons.camera_alt_outlined,
                            onPressed: () => context.push('/capture'),
                          ),
                  ),
                ),
              ];
            }
            final shown = visible.take(_shown).toList();
            return [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverToBoxAdapter(child: _Summary(records: records)),
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
  const _Summary({required this.records});
  final List<SoilRecord> records;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    final week = records.where((r) {
      final date = DateTime.tryParse(r.timestamp)?.toLocal();
      return date != null && !date.isBefore(monday) && !date.isAfter(now);
    }).length;
    final earned = records
        .where((r) => r.hasClassification)
        .map((r) => r.textureClass)
        .toSet()
        .intersection(_collectionClasses.toSet())
        .length;
    final cells = [
      ('${records.length}', 'análises', null),
      ('$week', 'nesta semana', '$week análises nesta semana'),
      ('$earned/12', 'classes', null),
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

final _collectionClasses = SoilTextureColors.referenceClasses.keys.toList();

class _Collection extends StatelessWidget {
  const _Collection({required this.records});
  final List<SoilRecord> records;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final name in _collectionClasses)
          Builder(
            builder: (context) {
              final earned = records.any((r) => r.textureClass == name);
              return Semantics(
                label: '$name, ${earned ? 'conquistada' : 'não conquistada'}',
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
                        Text(name, textAlign: TextAlign.center),
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
