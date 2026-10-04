import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.record});

  final SoilRecord record;

  @override
  Widget build(BuildContext context) {
    // The photograph and one way out: details, underneath, holds the rest
    // (SPEC 0125).
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ImageViewer(record: record),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.record});

  final SoilRecord record;

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
            child: Image.file(
              imageFile,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
        const _TopBar(),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

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
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: VisioIconButton(
              label: 'Fechar',
              icon: Icons.close,
              overPhoto: true,
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        ),
      ),
    );
  }
}
