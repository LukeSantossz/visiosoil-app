import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class DetailsPage extends ConsumerWidget {
  const DetailsPage({super.key, required this.recordId});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(soilRecordByIdProvider(recordId));

    return asyncRecord.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _RecordNotFoundView(),
      data: (record) {
        if (record == null) return const _RecordNotFoundView();
        return _DetailsContent(record: record, recordId: recordId);
      },
    );
  }
}

// --- Not Found ---

class _RecordNotFoundView extends StatelessWidget {
  const _RecordNotFoundView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text('Registro não encontrado', style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

// --- Main Content ---

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({required this.record, required this.recordId});

  final SoilRecord record;
  final int recordId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _HeroImageAppBar(record: record),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClassificationHeader(record: record),
                  const SizedBox(height: AppSpacing.xl),
                  _InfoSection(record: record),
                  const SizedBox(height: AppSpacing.xl),
                  _ActionButtons(recordId: recordId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Hero Image with SliverAppBar ---

class _HeroImageAppBar extends StatelessWidget {
  const _HeroImageAppBar({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final imageFile = File(record.imagePath);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheH = (280 * dpr).round();

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.onSurface,
      flexibleSpace: FlexibleSpaceBar(
        background: Image.file(
          imageFile,
          fit: BoxFit.cover,
          cacheHeight: cacheH,
          errorBuilder: (_, _, _) => Container(
            color: AppColors.surfaceVariant,
            child: const Center(
              child: Icon(
                Icons.broken_image,
                size: 48,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Classification Header ---

class _ClassificationHeader extends StatelessWidget {
  const _ClassificationHeader({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : AppColors.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Texture class name + color dot
        Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: textureColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                record.displayTextureClass,
                style: theme.textTheme.headlineMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Confidence badge + timestamp
        Row(
          children: [
            if (record.hasClassification) ...[
              _ConfidenceBadge(score: record.confidenceScore),
              const SizedBox(width: AppSpacing.md),
            ],
            Icon(
              Icons.access_time,
              size: 14,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              record.formattedTimestampCompact,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Confidence Badge ---

class _ConfidenceBadge extends StatelessWidget {
  const _ConfidenceBadge({required this.score});

  final double? score;

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();

    final pct = (score! * 100).round();
    final Color bg;
    final Color fg;
    final String label;

    if (pct >= 80) {
      bg = AppColors.primaryContainer;
      fg = AppColors.onPrimaryContainer;
      label = 'Alta';
    } else if (pct >= 60) {
      bg = AppColors.warningContainer;
      fg = const Color(0xFF6D4C1D);
      label = 'Média';
    } else {
      bg = AppColors.errorContainer;
      fg = AppColors.onErrorContainer;
      label = 'Baixa';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.borderRadiusPill,
      ),
      child: Text(
        '$pct% · $label',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
      ),
    );
  }
}

// --- Info Section ---

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Location
        _InfoTile(
          icon: Icons.location_on_outlined,
          title: 'Localização',
          value: record.hasValidAddress
              ? record.displayAddress
              : 'Endereço indisponível',
          subtitle: record.hasCoordinates
              ? record.formattedCoordinates
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        // Date
        _InfoTile(
          icon: Icons.calendar_today_outlined,
          title: 'Data da coleta',
          value: record.formattedTimestamp,
        ),
        if (record.hasClassification) ...[
          const SizedBox(height: AppSpacing.md),
          // Classification info
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

// --- Action Buttons ---

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.recordId});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Recommendations placeholder
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Plano de manejo em breve'),
              ),
            );
          },
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Ver plano de manejo'),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Share placeholder
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Compartilhamento em breve'),
              ),
            );
          },
          icon: const Icon(Icons.share_outlined),
          label: const Text('Compartilhar'),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Delete
        TextButton.icon(
          onPressed: () => _confirmAndDelete(context, ref),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Excluir registro'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.error,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir registro'),
        content: const Text(
          'Tem certeza que deseja excluir este registro? '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(soilRecordRepositoryProvider).deleteById(recordId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro excluído.')),
        );
        context.go('/');
      }
    }
  }
}
