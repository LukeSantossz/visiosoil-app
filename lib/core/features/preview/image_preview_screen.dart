import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/confidence_level.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class ImagePreviewScreen extends ConsumerWidget {
  const ImagePreviewScreen({super.key, required this.recordId});

  final int recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecord = ref.watch(soilRecordByIdProvider(recordId));

    return asyncRecord.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: LoadingIndicator(),
      ),
      error: (_, _) => _PreviewErrorView(
        onRetry: () => ref.invalidate(soilRecordByIdProvider(recordId)),
      ),
      data: (record) {
        if (record == null) return const _RecordNotFoundView();
        return _PreviewContent(record: record);
      },
    );
  }
}

/// Retryable load-error view: the shared error state under the shared bar, on
/// the theme's background rather than the viewer's black canvas (SPEC 0124).
/// Distinct from [_RecordNotFoundView]: a transient failure can be retried,
/// whereas a genuinely absent record cannot.
class _PreviewErrorView extends StatelessWidget {
  const _PreviewErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const VisioAppBar(),
      body: ErrorState(
        message: 'Não foi possível carregar o registro.',
        onRetry: onRetry,
      ),
    );
  }
}

class _RecordNotFoundView extends StatelessWidget {
  const _RecordNotFoundView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: VisioAppBar(),
      body: ErrorState(message: 'Registro não encontrado'),
    );
  }
}

class _PreviewContent extends ConsumerWidget {
  const _PreviewContent({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The photograph, then what the app knows about it (redesign v11 §3.8,
    // SPEC 0198), on the viewer's black canvas.
    final height = MediaQuery.sizeOf(context).height;
    return Theme(
      data: AppTheme.dark,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: VisioAppBar(
          title: AppStrings.photoTitle,
          centerTitle: false,
          leading: VisioIconButton(
            label: 'Fechar',
            icon: Icons.arrow_back,
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            VisioIconButton(
              label: 'Compartilhar',
              icon: Icons.share_outlined,
              onPressed: () => shareRecordWithConsent(context, ref, record),
            ),
          ],
        ),
        body: ListView(
          children: [
            SizedBox(
              height: height * 0.6,
              child: _ImageViewer(record: record),
            ),
            _RecordFacts(record: record),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: VisioButton(
                label: 'Excluir registro',
                icon: Icons.delete_outline,
                variant: VisioButtonVariant.destructive,
                onPressed: () => confirmAndDeleteRecord(context, ref, record),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        // Flies from the result's Detalhes tab (SPEC 0198).
        child: Hero(
          tag: recordPhotoHeroTag(record.id),
          child: Image.file(
            File(record.imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.broken_image,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row per fact the app knows; a fact it does not measure, such as the
/// mock's lux or distance, has no row (SPEC 0198).
class _RecordFacts extends StatelessWidget {
  const _RecordFacts({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    final score = record.confidenceScore;
    final model = record.modelVersion;
    final rows = <(String, String)>[
      if (record.hasClassification) ...[
        ('Classe estimada', record.displayTextureClass),
        if (score != null && score.isFinite)
          (
            'Confiança',
            '${ConfidenceLevel.fromScore(score).label} · '
                '${floorConfidencePercent(score)}%',
          ),
      ],
      ('Data e hora', Formatters.timestampDotted(record.timestamp)),
      if (record.hasCoordinates) ('Coordenadas', record.formattedCoordinates),
      if (record.horizontalAccuracy != null)
        ('Precisão', record.formattedHorizontalAccuracy),
      if (record.hasValidAddress) ('Endereço', record.displayAddress),
      if (model != null) ('Modelo', 'no aparelho · v$model'),
    ];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
