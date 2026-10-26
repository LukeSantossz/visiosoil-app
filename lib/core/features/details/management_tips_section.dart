import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/classification_failure_copy.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/collapse_on_correction.dart';
import 'package:visiosoil_app/core/widgets/empty_state.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/management_tips_controller_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';

/// Advisory "Dicas de manejo" section on the Soil Record details screen.
/// Cache-first display via [cachedManagementTipsProvider]; explicit generation
/// via [managementTipsControllerProvider]. Generation is manual; a failed
/// refresh preserves already-cached tips. Tips compose on the device from the
/// corpus the app holds (ADR 0022), so no action here waits on connectivity.
class ManagementTipsSection extends ConsumerStatefulWidget {
  const ManagementTipsSection({super.key, required this.record});

  final SoilRecord record;

  @override
  ConsumerState<ManagementTipsSection> createState() =>
      _ManagementTipsSectionState();
}

class _ManagementTipsSectionState extends ConsumerState<ManagementTipsSection> {
  bool _generating = false;
  ResearchFailureKind? _lastError;

  SoilRecord get _record => widget.record;

  Future<void> _generate() async {
    final uuid = _record.uuid;
    if (uuid == null) return;
    final hadTips =
        ref.read(cachedManagementTipsProvider(uuid)).value != null;
    setState(() {
      _generating = true;
      _lastError = null;
    });
    final failure =
        await ref.read(managementTipsControllerProvider).generate(_record);
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
          content: Text('Não foi possível atualizar as dicas. Tente novamente.'),
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
      body = ref.watch(cachedManagementTipsProvider(uuid)).when(
            loading: () => const _TipsLoading(),
            // A corrupt or unreadable cache entry surfaces here; fall back to
            // the empty state so the user can regenerate (overwriting the bad
            // entry) instead of being stuck.
            error: (_, _) => _empty(),
            data: (result) {
              if (_generating && result == null) return const _TipsLoading();
              if (result != null) {
                return _TipsData(
                  textureLabel: _record.displayTextureClass,
                  result: result,
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

    final showingError = _record.hasClassification &&
        uuid != null &&
        _lastError != null &&
        !_generating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dicas de manejo', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
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
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.palette.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TipsData extends StatelessWidget {
  const _TipsData({
    required this.textureLabel,
    required this.result,
    required this.generating,
    required this.onRefresh,
  });

  final String textureLabel;
  final ManagementTipsResult result;
  final bool generating;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abstained =
        result.status == ManagementTipsStatus.abstained || result.tips.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (abstained)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Não encontramos dicas de manejo com fontes confiáveis para este registro.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          // The class and how many tips it has (redesign v11 §3.9).
          Text(
            '$textureLabel · ${result.tips.length} dicas',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: context.palette.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          _TipsTimeline(tips: result.tips, sources: result.sources),
        ],
        if (result.sources.isNotEmpty) ...[
          _SourcesList(sources: result.sources),
          const SizedBox(height: AppSpacing.md),
        ],
        _DisclaimerBanner(text: _disclaimer(result.disclaimer)),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Atualizado em ${Formatters.timestamp(result.retrievedAt.toLocal().toIso8601String())}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.onSurfaceVariant),
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

/// The tips grouped by category on a timeline (redesign v11 §3.9,
/// SPEC 0198). Tips carry a category, not a crop phase, so the groups are the
/// categories, in a fixed order.
class _TipsTimeline extends StatelessWidget {
  const _TipsTimeline({required this.tips, required this.sources});

  final List<ManagementTip> tips;
  final List<TipSource> sources;

  static const List<(TipCategory?, String)> _groups = [
    (TipCategory.preparation, 'Preparo do solo'),
    (TipCategory.crops, 'Culturas'),
    (TipCategory.water, 'Água'),
    (TipCategory.other, 'Outras práticas'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final groups = [
      for (final (category, heading) in _groups)
        (
          heading,
          tips
              .where((tip) =>
                  tip.category == category ||
                  // A tip without a known category reads as "other".
                  (category == TipCategory.other && tip.category == null))
              .toList(),
        ),
    ].where((group) => group.$2.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var g = 0; g < groups.length; g++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The dot and the rule that joins the groups.
                SizedBox(
                  width: AppSpacing.xl,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: g == 0 ? palette.primary : palette.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.primary, width: 2),
                        ),
                      ),
                      if (g < groups.length - 1)
                        Expanded(
                          child: Container(width: 2, color: palette.outlineVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(groups[g].$1, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      for (final tip in groups[g].$2) ...[
                        _TipCard(tip: tip, sources: sources),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.sources});

  final ManagementTip tip;
  final List<TipSource> sources;

  static IconData _iconFor(TipCategory? category) => switch (category) {
        TipCategory.preparation => Icons.agriculture_outlined,
        TipCategory.crops => Icons.eco_outlined,
        TipCategory.water => Icons.water_drop_outlined,
        TipCategory.other || null => Icons.lightbulb_outline,
      };

  /// The first cited source, and how many more the tip cites.
  String? _sourceLine() {
    final cited = tip.citations
        .where((i) => i >= 0 && i < sources.length)
        .toList();
    if (cited.isEmpty) return null;
    final first = sources[cited.first];
    final name = [first.title, if (first.publisher != null) first.publisher!]
        .join(' · ');
    return cited.length > 1 ? '$name +${cited.length - 1}' : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final source = _sourceLine();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.borderRadiusLg,
        border: Border.all(color: palette.cardBorder, width: palette.edgeWidth),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.surfaceContainerHigh,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Icon(_iconFor(tip.category), color: palette.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tip.text, style: theme.textTheme.bodyMedium),
                if (source != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.bookmark_border,
                        size: 16,
                        color: palette.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          source,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: palette.onSurfaceVariant),
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
  const _SourcesList({required this.sources});

  final List<TipSource> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fontes',
          style: theme.textTheme.labelLarge
              ?.copyWith(color: context.palette.onSurfaceVariant),
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
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.palette.onSurfaceVariant),
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.warningContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(
          color: context.palette.bannerBorder(
            accent: context.palette.warning,
            onContainer: context.palette.onWarningContainer,
          ),
          width: context.palette.edgeWidth,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // onWarningContainer, as the confidence banner's icon: warning on
          // this container is 2.51 : 1, below 3 : 1 (SPEC 0127).
          Icon(
            Icons.info_outline,
            size: 20,
            color: context.palette.onWarningContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: context.palette.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
