import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:visiosoil_app/core/constants/storage_keys.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/core/widgets/visio_card.dart';
import 'package:visiosoil_app/models/soil_record.dart';

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
              // Última captura
              _LastCaptureCard(),
              const SizedBox(height: AppSpacing.xl),
              // CTA Principal
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

class _LastCaptureCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = Hive.box<SoilRecord>(StorageKeys.soilRecordsBox);

    return ValueListenableBuilder(
      valueListenable: box.listenable(),
      builder: (context, Box<SoilRecord> box, _) {
        if (box.isEmpty) {
          return const SizedBox.shrink();
        }

        final lastRecord = box.values.last;
        final imageFile = File(lastRecord.imagePath);
        final imageExists = imageFile.existsSync();

        return VisioCard(
          onTap: () => context.push('/details', extra: box.length - 1),
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: imageExists
                      ? Image.file(
                          imageFile,
                          fit: BoxFit.cover,
                        )
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
              // Info
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
                      lastRecord.formattedTimestampCompact,
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
      },
    );
  }
}
