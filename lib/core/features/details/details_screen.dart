import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/classification_header.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.recordId});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(soilRecordByIdProvider(recordId));

    return asyncRecord.when(
      loading: () => const Scaffold(
        body: LoadingIndicator(),
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
                  ClassificationHeader(record: record),
                  const SizedBox(height: AppSpacing.xl),
                  InfoSection(record: record),
                  const SizedBox(height: AppSpacing.xl),
                  ManagementTipsSection(record: record),
                  const SizedBox(height: AppSpacing.xl),
                  _ActionButtons(record: record),
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

// --- Action Buttons ---

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Share
        OutlinedButton.icon(
          onPressed: () => _shareRecord(context, ref),
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

  Future<void> _shareRecord(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    // Location is confidential client data; disclose it only on an explicit,
    // per-share opt-in. A record with no location shares directly.
    var includeLocation = false;
    if (record.hasCoordinates || record.hasValidAddress) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Incluir localização?'),
          content: const Text(
            'As coordenadas exatas do local ficarão visíveis para quem '
            'receber o compartilhamento.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Compartilhar sem localização'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Incluir localização'),
            ),
          ],
        ),
      );
      // Dismissing the dialog (barrier tap / back) cancels the share.
      if (choice == null) return;
      includeLocation = choice;
    }

    try {
      await ref
          .read(shareServiceProvider)
          .shareRecord(record, includeLocation: includeLocation);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível compartilhar o registro.'),
        ),
      );
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Excluir registro',
      message: 'Tem certeza que deseja excluir este registro? '
          'Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir',
    );

    if (confirmed && context.mounted && record.id != null) {
      await ref.read(soilRecordRepositoryProvider).deleteById(record.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro excluído.')),
        );
        context.go('/');
      }
    }
  }
}
