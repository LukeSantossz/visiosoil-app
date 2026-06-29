import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/empty_state.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_controller_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';

/// Advisory "Dicas de manejo" section on the Soil Record details screen.
/// Cache-first display via [cachedManagementTipsProvider]; explicit generation
/// via [managementTipsControllerProvider]. Generation is manual; a failed
/// refresh preserves already-cached tips.
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
      body = const EmptyState(
        icon: Icons.eco_outlined,
        title: 'Solo não classificado',
        description:
            'Classifique o solo deste registro para gerar dicas de manejo.',
      );
    } else {
      final online = ref.watch(connectivityStatusProvider).value !=
          ConnectivityStatus.offline;
      body = ref.watch(cachedManagementTipsProvider(uuid)).when(
            loading: () => const _TipsLoading(),
            // A corrupt or unreadable cache entry surfaces here; fall back to
            // the empty/offline state so the user can regenerate (overwriting
            // the bad entry) instead of being stuck.
            error: (_, _) => _emptyOrOffline(online),
            data: (result) {
              if (_generating && result == null) return const _TipsLoading();
              if (result != null) {
                return _TipsData(
                  result: result,
                  online: online,
                  generating: _generating,
                  onRefresh: _generate,
                );
              }
              if (_lastError != null) {
                return ErrorState(
                  message: _messageFor(_lastError!),
                  onRetry: online ? _generate : null,
                );
              }
              return _emptyOrOffline(online);
            },
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dicas de manejo', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        body,
      ],
    );
  }

  Widget _emptyOrOffline(bool online) {
    if (!online) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Sem conexão',
        description: 'Conecte-se à internet para gerar dicas de manejo.',
      );
    }
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
            'Gerando dicas de manejo…',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TipsData extends StatelessWidget {
  const _TipsData({
    required this.result,
    required this.online,
    required this.generating,
    required this.onRefresh,
  });

  final ManagementTipsResult result;
  final bool online;
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
        else
          for (final tip in result.tips) ...[
            _TipCard(tip: tip, sourceCount: result.sources.length),
            const SizedBox(height: AppSpacing.md),
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
              ?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        VisioButton(
          label: 'Atualizar dicas',
          icon: Icons.refresh,
          variant: VisioButtonVariant.secondary,
          expanded: true,
          isLoading: generating,
          onPressed: online ? () => onRefresh() : null,
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

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip, required this.sourceCount});

  final ManagementTip tip;
  final int sourceCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final citations =
        tip.citations.where((i) => i >= 0 && i < sourceCount).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.borderRadiusLg,
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip.text, style: theme.textTheme.bodyMedium),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [for (final i in citations) _CitationChip(label: i + 1)],
            ),
          ],
        ],
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.label});

  final int label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.borderRadiusPill,
      ),
      child: Text(
        '[$label]',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimaryContainer,
            ),
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
              ?.copyWith(color: AppColors.onSurfaceVariant),
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
              ?.copyWith(color: AppColors.onSurfaceVariant),
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
        color: AppColors.warningContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
