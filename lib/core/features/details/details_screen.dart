import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/classification_header.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
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
      error: (_, _) => _DetailsErrorView(
        onRetry: () => ref.invalidate(soilRecordByIdProvider(recordId)),
      ),
      data: (record) {
        if (record == null) return const _RecordNotFoundView();
        return _DetailsContent(record: record, recordId: recordId);
      },
    );
  }
}

// --- Load Error (retryable) ---

class _DetailsErrorView extends StatelessWidget {
  const _DetailsErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const VisioAppBar(title: 'Detalhes'),
      body: ErrorState(
        message: 'Não foi possível carregar o registro.',
        onRetry: onRetry,
      ),
    );
  }
}

// --- Not Found ---

class _RecordNotFoundView extends StatelessWidget {
  const _RecordNotFoundView();

  @override
  Widget build(BuildContext context) {
    // The shared error state, with nothing to retry (SPEC 0124).
    return const Scaffold(
      appBar: VisioAppBar(title: 'Detalhes'),
      body: ErrorState(message: 'Registro não encontrado'),
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
          // The page scrolls under the navigation bar on Android 12 and later
          // (SPEC 0109), so the last action ends above it.
          SliverSafeArea(
            top: false,
            sliver: SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
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
      backgroundColor: context.palette.surface,
      foregroundColor: context.palette.onSurface,
      // The back button sits over the photograph, whose top is the white A4
      // sheet (ADR 0017), so it cannot take the theme's text colour. It takes
      // the photo viewer's scrim instead, which reads in both themes
      // (SPEC 0107).
      leading: Navigator.canPop(context)
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: IconButton(
                // A literal: the app registers no pt-BR Material localizations,
                // so backButtonTooltip would read "Back" (SPEC 0118).
                tooltip: 'Voltar',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            )
          : null,
      flexibleSpace: FlexibleSpaceBar(
        // Below the status bar, so its icons sit on the theme's surface rather
        // than on the photograph.
        background: Padding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          // A labelled button that opens the full-screen viewer, its ink on a
          // transparent Material over the photograph (SPEC 0125).
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                imageFile,
                fit: BoxFit.cover,
                cacheHeight: cacheH,
                errorBuilder: (_, _, _) => Container(
                  color: context.palette.surfaceVariant,
                  child: Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 48,
                      color: context.palette.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Ampliar foto',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => context.push('/preview', extra: record.id),
                  ),
                ),
              ),
            ],
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
        // Delete keeps 24 dp from Share against a mis-tap (SPEC 0118).
        const SizedBox(height: AppSpacing.xl),
        // Delete
        VisioButton(
          label: 'Excluir registro',
          onPressed: () => _confirmAndDelete(context, ref),
          icon: Icons.delete_outline,
          variant: VisioButtonVariant.destructive,
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
