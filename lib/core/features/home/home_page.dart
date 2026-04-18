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

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: const VisioAppBar(title: 'VisioSoil'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const _LastCaptureCard(),
              const SizedBox(height: AppSpacing.xl),
              VisioButton(
                label: 'Nova Captura',
                icon: Icons.camera_alt,
                onPressed: () => context.push('/capture'),
                expanded: true,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LastCaptureCard extends ConsumerWidget {
  const _LastCaptureCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final latest = ref.watch(latestSoilRecordProvider);

    return latest.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (record) {
        if (record == null) {
          return const SizedBox.shrink();
        }
        return _LastCaptureContent(record: record, theme: theme);
      },
    );
  }
}

class _LastCaptureContent extends StatelessWidget {
  const _LastCaptureContent({required this.record, required this.theme});

  final SoilRecord record;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final imageFile = File(record.imagePath);
    final imageExists = imageFile.existsSync();

    return VisioCard(
      onTap: () => context.push('/details', extra: record.id!),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60,
              height: 60,
              child: imageExists
                  ? Image.file(imageFile, fit: BoxFit.cover)
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.image_not_supported,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Última captura',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  record.formattedTimestampCompact,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
