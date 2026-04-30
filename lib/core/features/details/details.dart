import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/core/widgets/visio_card.dart';
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
        appBar: VisioAppBar(title: 'Detalhes'),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _RecordNotFoundView(),
      data: (record) {
        if (record == null) {
          return const _RecordNotFoundView();
        }
        return _DetailsContent(record: record, recordId: recordId);
      },
    );
  }
}

class _RecordNotFoundView extends StatelessWidget {
  const _RecordNotFoundView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const VisioAppBar(title: 'Detalhes'),
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

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({required this.record, required this.recordId});

  final SoilRecord record;
  final int recordId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const VisioAppBar(title: 'Detalhes'),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImageHeader(imagePath: record.imagePath),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TimestampCard(timestamp: record.formattedTimestamp),
                  const SizedBox(height: AppSpacing.md),
                  _LocationCard(record: record),
                  const SizedBox(height: AppSpacing.md),
                  _ClassificationCard(record: record),
                  const SizedBox(height: AppSpacing.xl),
                  _DeleteButton(recordId: recordId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageHeader extends StatelessWidget {
  const _ImageHeader({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageFile = File(imagePath);
    final imageExists = imageFile.existsSync();

    return AspectRatio(
      aspectRatio: 4 / 3,
      child: imageExists
          ? Image.file(imageFile, fit: BoxFit.cover)
          : Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  Icons.broken_image,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
    );
  }
}

class _TimestampCard extends StatelessWidget {
  const _TimestampCard({required this.timestamp});

  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return VisioCard(
      child: Row(
        children: [
          Icon(Icons.access_time, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data e Hora',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(timestamp, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return VisioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Localização',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      record.hasValidAddress
                          ? record.displayAddress
                          : 'Indisponível para imagens da galeria',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (record.hasCoordinates) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _CoordinateItem(
                    label: 'Latitude',
                    value: record.latitude!.toStringAsFixed(6),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _CoordinateItem(
                    label: 'Longitude',
                    value: record.longitude!.toStringAsFixed(6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CoordinateItem extends StatelessWidget {
  const _CoordinateItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

class _ClassificationCard extends StatelessWidget {
  const _ClassificationCard({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return VisioCard(
      child: Row(
        children: [
          Icon(
            Icons.eco,
            color: record.hasClassification
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Classificação de Textura',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  record.displayTextureClass,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight:
                        record.hasClassification ? FontWeight.bold : null,
                  ),
                ),
                if (record.hasClassification) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Confiança: ${record.formattedConfidence}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

class _DeleteButton extends ConsumerWidget {
  const _DeleteButton({required this.recordId});

  final int recordId;

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await _showDeleteConfirmation(context);

    if (confirmed == true && context.mounted) {
      await _deleteRecord(context, ref);
    }
  }

  Future<bool?> _showDeleteConfirmation(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir registro'),
        content: const Text(
          'Tem certeza que deseja excluir este registro? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(BuildContext context, WidgetRef ref) async {
    await ref.read(soilRecordRepositoryProvider).deleteById(recordId);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Registro excluído.')));
      // Volta para a home, pulando a tela de preview.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return VisioButton(
      label: 'Excluir Registro',
      icon: Icons.delete_outline,
      onPressed: () => _confirmAndDelete(context, ref),
      variant: VisioButtonVariant.secondary,
      expanded: true,
    );
  }
}
