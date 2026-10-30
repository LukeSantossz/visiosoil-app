import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/collapse_on_correction.dart';
import 'package:visiosoil_app/core/widgets/empty_state.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/settings_switch_tile.dart';
import 'package:visiosoil_app/core/widgets/settings_tile.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/management_tips_controller_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';

/// Advisory "Dicas de manejo" section on the Soil Record details screen.
/// Cache-first display via [cachedManagementTipsProvider]; generation via
/// [managementTipsControllerProvider] runs automatically once per section state
/// after an empty cache read. Manual generation and retry remain available; a
/// failed refresh preserves already-cached tips. Tips compose on the device
/// from the corpus the app holds (ADR 0022), so no action here waits on
/// connectivity.
class ManagementTipsSection extends ConsumerStatefulWidget {
  const ManagementTipsSection({
    super.key,
    required this.record,
    this.asPage = false,
    this.hiddenCategories = const {},
  });

  final SoilRecord record;

  /// Categories the Dicas tab's filter turned off (SPEC 0209). A tip without
  /// a category counts as [TipCategory.other].
  final Set<TipCategory> hiddenCategories;

  /// The Dicas tab: the record heads the page in place of the section's
  /// title (PNG 20, SPEC 0205).
  final bool asPage;

  @override
  ConsumerState<ManagementTipsSection> createState() =>
      _ManagementTipsSectionState();
}

class _ManagementTipsSectionState extends ConsumerState<ManagementTipsSection> {
  bool _generating = false;
  bool _autoGenerationAttempted = false;
  ResearchFailureKind? _lastError;

  SoilRecord get _record => widget.record;

  @override
  void didUpdateWidget(covariant ManagementTipsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.uuid != widget.record.uuid) {
      _autoGenerationAttempted = false;
      _lastError = null;
    }
  }

  Future<void> _generate() async {
    final uuid = _record.uuid;
    if (uuid == null) return;
    final hadTips = ref.read(cachedManagementTipsProvider(uuid)).value != null;
    setState(() {
      _generating = true;
      _lastError = null;
    });
    final failure = await ref
        .read(managementTipsControllerProvider)
        .generate(_record);
    if (!mounted) return;
    if (failure == null) {
      // Re-read the freshly cached tips before clearing the loading flag, so
      // the section goes straight from loading to data without a one-frame
      // flash of the empty state during the cache re-read.
      ref.invalidate(cachedManagementTipsProvider(uuid));
      await ref.read(cachedManagementTipsProvider(uuid).future);
      if (!mounted) return;
    }
    setState(() {
      _generating = false;
      if (failure != null && !hadTips) _lastError = failure;
    });
    if (failure != null && hadTips) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível atualizar as dicas. Tente novamente.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    final uuid = _record.uuid;
    if (!_record.hasClassification || uuid == null) {
      final failure = _record.classificationFailure;
      body = EmptyState(
        icon: Icons.eco_outlined,
        title: 'Solo não classificado',
        description: [
          // The reason first, in the capture chip's words (SPEC 0173).
          if (failure != null) classificationFailureChip(failure).label,
          'Este registro foi salvo sem a classe de textura, e as dicas '
              'dependem dela. Para obtê-las, capture a amostra de novo '
              'seguindo o passo a passo.',
        ].join('\n\n'),
      );
    } else {
      body = ref
          .watch(cachedManagementTipsProvider(uuid))
          .when(
            loading: () => const _TipsLoading(),
            // A corrupt or unreadable cache entry surfaces here; fall back to
            // the empty state so the user can regenerate (overwriting the bad
            // entry) instead of being stuck.
            error: (_, _) => _empty(),
            data: (result) {
              if (result == null && !_autoGenerationAttempted && !_generating) {
                _autoGenerationAttempted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _generate();
                });
                return const _TipsLoading();
              }
              if (_generating && result == null) return const _TipsLoading();
              if (result != null) {
                return _TipsData(
                  textureLabel: _record.displayTextureClass,
                  showCount: !widget.asPage,
                  result: result,
                  hiddenCategories: widget.hiddenCategories,
                  generating: _generating,
                  onRefresh: _generate,
                );
              }
              if (_lastError != null) {
                return ErrorState(
                  message: _messageFor(_lastError!),
                  onRetry: _generate,
                );
              }
              return _empty();
            },
          );
    }

    final showingError =
        _record.hasClassification &&
        uuid != null &&
        _lastError != null &&
        !_generating;
    final cached = uuid == null
        ? null
        : ref.watch(cachedManagementTipsProvider(uuid)).value;
    final count = cached == null
        ? null
        : shownTips(cached.tips, widget.hiddenCategories).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.asPage) ...[
          _RecordHeader(record: _record, tipCount: count),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: context.palette.divider),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          Text('Dicas de manejo', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
        ],
        CollapseOnCorrection(isError: showingError, child: body),
      ],
    );
  }

  Widget _empty() {
    return EmptyState(
      icon: Icons.tips_and_updates_outlined,
      title: 'Sem dicas de manejo ainda',
      description: 'Gere dicas com fontes para este solo.',
      action: VisioButton(
        label: 'Gerar dicas',
        icon: Icons.tips_and_updates_outlined,
        isLoading: _generating,
        onPressed: _generate,
      ),
    );
  }

  String _messageFor(ResearchFailureKind kind) {
    switch (kind) {
      case ResearchFailureKind.corpusUnavailable:
        return 'As dicas de manejo ainda não estão disponíveis nesta versão do app.';
      case ResearchFailureKind.timeout:
      case ResearchFailureKind.network:
        return 'Falha de conexão. Verifique sua internet e tente novamente.';
      case ResearchFailureKind.rateLimited:
        return 'Muitas solicitações. Aguarde um momento e tente novamente.';
      case ResearchFailureKind.unauthenticated:
        return 'Entre na sua conta para gerar dicas de manejo.';
      case ResearchFailureKind.malformedResponse:
        return 'Resposta inválida do serviço. Tente novamente.';
      case ResearchFailureKind.invalidRecord:
      case ResearchFailureKind.upstreamUnavailable:
        return 'Não foi possível gerar as dicas agora. Tente novamente mais tarde.';
    }
  }
}

class _TipsLoading extends StatelessWidget {
  const _TipsLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const LoadingIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Carregando dicas',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsData extends StatelessWidget {
  const _TipsData({
    required this.textureLabel,
    required this.showCount,
    required this.result,
    required this.hiddenCategories,
    required this.generating,
    required this.onRefresh,
  });

  final String textureLabel;

  /// The class and count line; the Dicas tab's header says it instead.
  final bool showCount;
  final ManagementTipsResult result;
  final Set<TipCategory> hiddenCategories;
  final bool generating;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abstained =
        result.status == ManagementTipsStatus.abstained || result.tips.isEmpty;
    final tips = shownTips(result.tips, hiddenCategories);

    // The disclaimer leads, as PNG 20 draws it (SPEC 0205).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DisclaimerBanner(text: _disclaimer(result.disclaimer)),
        const SizedBox(height: AppSpacing.lg),
        if (abstained)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Não encontramos dicas de manejo com fontes confiáveis para este registro.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          if (showCount) ...[
            // The class and how many tips it has (redesign v11 §3.9).
            Text(
              '$textureLabel · ${Formatters.count(tips.length, 'dica', 'dicas')}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (tips.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Nenhuma dica nas categorias escolhidas.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            _TipsTimeline(tips: tips, sources: result.sources),
        ],
        if (result.sources.isNotEmpty) ...[
          _SourcesList(sources: result.sources, consulted: abstained),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(
          'Atualizado em ${Formatters.timestamp(result.retrievedAt.toLocal().toIso8601String())}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        VisioButton(
          label: 'Atualizar dicas',
          icon: Icons.refresh,
          variant: VisioButtonVariant.secondary,
          expanded: true,
          isLoading: generating,
          onPressed: () => onRefresh(),
        ),
      ],
    );
  }

  String _disclaimer(String value) {
    if (value.trim().isNotEmpty) return value;
    return 'Dicas de manejo consultivas, baseadas em fontes públicas. '
        'Não substituem avaliação técnica presencial.';
  }
}

/// [tips] without the categories in [hidden]; a tip without a category is
/// never hidden (SPEC 0209).
List<ManagementTip> shownTips(
  List<ManagementTip> tips,
  Set<TipCategory> hidden,
) => hidden.isEmpty
    ? tips
    : [
        for (final tip in tips)
          if (tip.category == null || !hidden.contains(tip.category)) tip,
      ];

/// The categories the filter sheet offers: those [tips] carry. A tip without
/// one is not filed under "Outras práticas", so tips that carry none leave
/// nothing to filter (SPEC 0209).
Set<TipCategory> filterableCategories(List<ManagementTip> tips) => {
  for (final tip in tips) ?tip.category,
};

/// The category headings, in the timeline's order.
const Map<TipCategory, String> tipCategoryLabels = {
  TipCategory.preparation: 'Preparo do solo',
  TipCategory.crops: 'Culturas',
  TipCategory.water: 'Água',
  TipCategory.other: 'Outras práticas',
};

/// The Dicas tab's filter: one switch per category [present], on unless in
/// [hidden]. Each change hands the new hidden set to [onChanged] (SPEC 0209).
Future<void> showTipsFilterSheet(
  BuildContext context, {
  required Set<TipCategory> present,
  required Set<TipCategory> hidden,
  required ValueChanged<Set<TipCategory>> onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) =>
      _TipsFilterSheet(present: present, hidden: hidden, onChanged: onChanged),
);

class _TipsFilterSheet extends StatefulWidget {
  const _TipsFilterSheet({
    required this.present,
    required this.hidden,
    required this.onChanged,
  });

  final Set<TipCategory> present;
  final Set<TipCategory> hidden;
  final ValueChanged<Set<TipCategory>> onChanged;

  @override
  State<_TipsFilterSheet> createState() => _TipsFilterSheetState();
}

class _TipsFilterSheetState extends State<_TipsFilterSheet> {
  late Set<TipCategory> _hidden = {...widget.hidden};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtrar dicas', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            if (widget.present.isEmpty)
              Text(
                'Estas dicas não têm categorias para filtrar.',
                style: theme.textTheme.bodyMedium,
              )
            else
              SettingsGroup(
                children: [
                  for (final MapEntry(key: category, value: label)
                      in tipCategoryLabels.entries)
                    if (widget.present.contains(category))
                      SettingsSwitchTile(
                        icon: _TipCard.iconFor(category),
                        title: label,
                        value: !_hidden.contains(category),
                        onChanged: (on) {
                          setState(
                            () => _hidden = on
                                ? ({..._hidden}..remove(category))
                                : {..._hidden, category},
                          );
                          widget.onChanged(_hidden);
                        },
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The tips on a timeline (redesign v11 §3.9, SPEC 0198, SPEC 0209). When
/// every tip names its crop phase, the groups are the phases in crop order,
/// the first marked "Agora" and the second "Próximo". Otherwise they are the
/// categories, in a fixed order, unmarked.
class _TipsTimeline extends StatelessWidget {
  const _TipsTimeline({required this.tips, required this.sources});

  final List<ManagementTip> tips;
  final List<TipSource> sources;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final byPhase = tips.every((tip) => tip.phase != null);
    final groups = byPhase
        ? [
            for (final phase in TipPhase.values)
              (phase.label, tips.where((tip) => tip.phase == phase).toList()),
          ].where((group) => group.$2.isNotEmpty).toList()
        : [
            for (final MapEntry(key: category, value: heading)
                in tipCategoryLabels.entries)
              (
                heading,
                tips
                    .where(
                      (tip) =>
                          tip.category == category ||
                          // A tip without a known category reads as "other".
                          (category == TipCategory.other &&
                              tip.category == null),
                    )
                    .toList(),
              ),
          ].where((group) => group.$2.isNotEmpty).toList();

    // A 24 dp gutter with a 12 dp dot, the first filled; 17 sp titles
    // 12 dp after it; 16 dp between groups (PNG 20, SPEC 0205).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < groups.length; g++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: AppSpacing.xl,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        key: Key('tips-dot-$g'),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: g == 0 ? palette.primary : palette.surface,
                          shape: BoxShape.circle,
                          border: g == 0
                              ? null
                              : Border.all(color: palette.outline, width: 2),
                        ),
                      ),
                      if (g < groups.length - 1)
                        Expanded(
                          child: Container(
                            width: palette.edgeWidth,
                            color: palette.divider,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: g < groups.length - 1 ? AppSpacing.lg : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: AppSpacing.sm,
                          children: [
                            Text(
                              groups[g].$1,
                              style: AppTypography.resized(
                                theme.textTheme.titleMedium!,
                                16,
                                height: 24 / 16,
                              ),
                            ),
                            if (byPhase && g < 2)
                              _PhaseChip(
                                boxKey: Key('tips-phase-chip-$g'),
                                now: g == 0,
                              ),
                          ],
                        ),
                        for (final tip in groups[g].$2) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _TipCard(tip: tip, sources: sources),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Agora" on the first phase, "Próximo" on the second (PNG 20, SPEC 0209).
class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.boxKey, required this.now});

  final Key boxKey;
  final bool now;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: boxKey,
      // 24 dp: the 16 dp line and 4 dp above and below it.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: now ? palette.selected : palette.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: palette.highContrast
            ? Border.all(color: palette.cardBorder, width: palette.edgeWidth)
            : null,
      ),
      child: Text(
        now ? 'Agora' : 'Próximo',
        style: AppTypography.weighted(
          AppTypography.resized(
            Theme.of(context).textTheme.labelMedium!,
            12,
            height: 16 / 12,
          ),
          600,
        ).copyWith(color: now ? palette.primaryText : palette.onSurfaceVariant),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.sources});

  final ManagementTip tip;
  final List<TipSource> sources;

  static IconData iconFor(TipCategory? category) => switch (category) {
    TipCategory.preparation => LucideIcons.tractor,
    TipCategory.crops => LucideIcons.sprout,
    TipCategory.water => LucideIcons.droplets,
    TipCategory.other || null => LucideIcons.lightbulb,
  };

  /// The first cited source, and how many more the tip cites.
  String? _sourceLine() {
    final cited = tip.citations
        .where((i) => i >= 0 && i < sources.length)
        .toList();
    if (cited.isEmpty) return null;
    final first = sources[cited.first];
    final name = [
      first.title,
      if (first.publisher != null) first.publisher!,
    ].join(' · ');
    return cited.length > 1 ? '$name +${cited.length - 1}' : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final source = _sourceLine();

    // On surface with a divider edge, a 40 dp icon tile, the text at 15/20
    // and the source under a bookmark (PNG 20, SPEC 0205).
    return Container(
      key: const Key('tip-card'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.highContrast ? palette.cardBorder : palette.divider,
          width: palette.edgeWidth,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const Key('tip-icon-tile'),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              iconFor(tip.category),
              size: 20,
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A titled tip sets its title over the text in
                // `onSurfaceVariant` (PNG 20, SPEC 0209).
                if (tip.title != null) ...[
                  Text(
                    tip.title!,
                    style: AppTypography.weighted(
                      AppTypography.resized(
                        theme.textTheme.titleMedium!,
                        15,
                        height: 22 / 15,
                      ),
                      600,
                    ).copyWith(color: palette.onSurface),
                  ),
                ],
                Text(
                  tip.text,
                  style:
                      AppTypography.resized(
                        theme.textTheme.bodyMedium!,
                        14,
                        height: 20 / 14,
                      ).copyWith(
                        color: tip.title == null
                            ? null
                            : palette.onSurfaceVariant,
                      ),
                ),
                if (source != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.bookmark,
                        size: 16,
                        color: palette.textTertiary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          source,
                          style: AppTypography.resized(
                            theme.textTheme.bodySmall!,
                            12,
                            height: 16 / 12,
                          ).copyWith(color: palette.textTertiary),
                        ),
                      ),
                    ],
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

class _SourcesList extends StatelessWidget {
  const _SourcesList({required this.sources, required this.consulted});

  final List<TipSource> sources;

  /// The sources were read but support no tip, so the heading says only that
  /// they were consulted (SPEC 0233).
  final bool consulted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          consulted ? 'Fontes consultadas' : 'Fontes',
          style: theme.textTheme.labelLarge?.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < sources.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _SourceTile(index: i + 1, source: sources[i]),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.index, required this.source});

  final int index;
  final TipSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final publisher = source.publisher;
    final title = publisher == null || publisher.isEmpty
        ? source.title
        : '${source.title} — $publisher';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$index. $title', style: theme.textTheme.bodySmall),
        Text(
          source.url,
          style: theme.textTheme.bodySmall?.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    // Borderless outside high contrast, radius 12, the text at 15/20
    // (PNG 20, SPEC 0205).
    return Container(
      key: const Key('tips-disclaimer'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.warningContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: palette.highContrast
            ? Border.all(
                color: palette.bannerBorder(
                  accent: palette.warning,
                  onContainer: palette.onWarningContainer,
                ),
                width: palette.edgeWidth,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // onWarningContainer, as the confidence banner's icon: warning on
          // this container is 2.51 : 1, below 3 : 1 (SPEC 0127).
          Icon(LucideIcons.info, size: 20, color: palette.onWarningContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: AppTypography.resized(
                theme.textTheme.bodyMedium!,
                14,
                height: 20 / 14,
              ).copyWith(color: palette.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Dicas tab's head: the record's photograph, its class and labels, and
/// how many tips it has (PNG 20, SPEC 0205).
class _RecordHeader extends StatelessWidget {
  const _RecordHeader({required this.record, required this.tipCount});

  final SoilRecord record;
  final int? tipCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    // The sample alone; the field label is not shown (SPEC 0220).
    final labels = record.labelsSummary;
    final placeholder = ColoredBox(color: palette.surfaceContainerHigh);
    return Row(
      children: [
        ClipRRect(
          borderRadius: AppRadius.borderRadiusMd,
          child: SizedBox(
            key: const Key('tips-record-photo'),
            width: 56,
            height: 56,
            child: record.imagePath.isEmpty
                ? placeholder
                : Image.file(
                    File(record.imagePath),
                    fit: BoxFit.cover,
                    cacheWidth: 168,
                    frameBuilder: (_, child, frame, sync) =>
                        sync || frame != null ? child : placeholder,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.displayTextureClass,
                style: AppTypography.resized(
                  theme.textTheme.titleMedium!,
                  17,
                  height: 24 / 17,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
              Text(
                labels.isEmpty ? record.formattedTimestampCompact : labels,
                style: AppTypography.resized(
                  theme.textTheme.bodyMedium!,
                  15,
                  height: 20 / 15,
                ).copyWith(color: palette.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (tipCount != null && tipCount! > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
            constraints: const BoxConstraints(minHeight: 24),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              Formatters.count(tipCount!, 'dica', 'dicas'),
              style:
                  AppTypography.resized(
                    theme.textTheme.labelMedium!,
                    13,
                    height: 18 / 13,
                  ).copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                    color: palette.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
