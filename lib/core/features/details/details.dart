import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:visiosoil_app/core/constants/storage_keys.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/core/widgets/visio_card.dart';
import 'package:visiosoil_app/models/soil_record.dart';

class DetailsPage extends StatelessWidget {
  const DetailsPage({
    super.key,
    required this.recordIndex,
  });

  final int recordIndex;

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<SoilRecord>(StorageKeys.soilRecordsBox);

    // Valida se o índice ainda é válido (pode ter sido deletado)
    if (recordIndex < 0 || recordIndex >= box.length) {
      return const _RecordNotFoundView();
    }

    final record = box.getAt(recordIndex);
    if (record == null) {
      return const _RecordNotFoundView();
    }

    return _DetailsContent(record: record, recordIndex: recordIndex);
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
  const _DetailsContent({
    required this.record,
    required this.recordIndex,
  });

  final SoilRecord record;
  final int recordIndex;

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
                  const SizedBox(height: AppSpacing.xl),
                  _DeleteButton(recordIndex: recordIndex),
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
                    Text(record.displayAddress, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _CoordinateItem(
                  label: 'Latitude',
                  value: record.latitude.toStringAsFixed(6),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _CoordinateItem(
                  label: 'Longitude',
                  value: record.longitude.toStringAsFixed(6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoordinateItem extends StatelessWidget {
  const _CoordinateItem({
    required this.label,
    required this.value,
  });

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

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.recordIndex});

  final int recordIndex;

  Future<void> _confirmAndDelete(BuildContext context) async {
    final confirmed = await _showDeleteConfirmation(context);

    if (confirmed == true && context.mounted) {
      await _deleteRecord(context);
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

  Future<void> _deleteRecord(BuildContext context) async {
    final box = Hive.box<SoilRecord>(StorageKeys.soilRecordsBox);

    // Verifica se o índice ainda é válido antes de deletar
    if (recordIndex >= 0 && recordIndex < box.length) {
      await box.deleteAt(recordIndex);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro excluído.')),
      );
      // Volta para o histórico, pulando a tela de preview
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisioButton(
      label: 'Excluir Registro',
      icon: Icons.delete_outline,
      onPressed: () => _confirmAndDelete(context),
      variant: VisioButtonVariant.secondary,
      expanded: true,
    );
  }
}
