import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:visiosoil_app/core/constants/storage_keys.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/soil_record.dart';

class ImagePreviewScreen extends StatelessWidget {
  const ImagePreviewScreen({
    super.key,
    required this.recordIndex,
  });

  final int recordIndex;

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<SoilRecord>(StorageKeys.soilRecordsBox);

    // Valida se o índice ainda é válido (pode ter sido deletado)
    if (recordIndex < 0 || recordIndex >= box.length) {
      return _RecordNotFoundView(onBack: () => context.pop());
    }

    final record = box.getAt(recordIndex);
    if (record == null) {
      return _RecordNotFoundView(onBack: () => context.pop());
    }

    return _PreviewContent(record: record, recordIndex: recordIndex);
  }
}

class _RecordNotFoundView extends StatelessWidget {
  const _RecordNotFoundView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 48),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Registro não encontrado',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(onPressed: onBack, child: const Text('Voltar')),
          ],
        ),
      ),
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.record,
    required this.recordIndex,
  });

  final SoilRecord record;
  final int recordIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(child: _ImageViewer(record: record, recordIndex: recordIndex)),
          _InfoPanel(record: record),
        ],
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({
    required this.record,
    required this.recordIndex,
  });

  final SoilRecord record;
  final int recordIndex;

  @override
  Widget build(BuildContext context) {
    final imageFile = File(record.imagePath);

    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: imageFile.existsSync()
                ? Image.file(imageFile, fit: BoxFit.contain)
                : const Icon(Icons.broken_image, color: Colors.white54, size: 64),
          ),
        ),
        _TopBar(recordIndex: recordIndex),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.recordIndex});

  final int recordIndex;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleIconButton(
                icon: Icons.arrow_back,
                onPressed: () => context.pop(),
              ),
              _CircleIconButton(
                icon: Icons.info_outline,
                onPressed: () => context.push('/details', extra: recordIndex),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      color: Colors.white,
      style: IconButton.styleFrom(backgroundColor: Colors.black45),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DragHandle(),
              _InfoRow(
                icon: Icons.access_time,
                label: 'Capturado em',
                value: record.formattedTimestamp,
              ),
              if (record.hasValidAddress || record.hasCoordinates) ...[
                const SizedBox(height: AppSpacing.md),
                _InfoRow(
                  icon: Icons.location_on,
                  label: 'Localização',
                  value: record.hasValidAddress
                      ? record.address
                      : record.formattedCoordinates,
                ),
              ],
              if (record.hasCoordinates && record.hasValidAddress) ...[
                const SizedBox(height: AppSpacing.sm),
                _CoordinatesSubtext(coordinates: record.formattedCoordinates),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoordinatesSubtext extends StatelessWidget {
  const _CoordinatesSubtext({required this.coordinates});

  final String coordinates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 28),
      child: Text(
        coordinates,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
