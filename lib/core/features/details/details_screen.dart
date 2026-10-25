import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/classification_header.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/labels_dialog.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_error_block.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_overview.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import 'package:visiosoil_app/providers/soil_sample_provider.dart';

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

/// The result screen's tabs (redesign v11 §3.6, SPEC 0194).
enum ResultTab { overview, management, details }

class _DetailsContent extends ConsumerStatefulWidget {
  const _DetailsContent({required this.record, required this.recordId});

  final SoilRecord record;
  final int recordId;

  @override
  ConsumerState<_DetailsContent> createState() => _DetailsContentState();
}

class _DetailsContentState extends ConsumerState<_DetailsContent>
    with SingleTickerProviderStateMixin {
  /// The blocks that rise in: the header, the tab control and the tab, or
  /// the error block and the details below it.
  static const int _risingBlocks = 3;
  static const Duration _blockStagger = Duration(milliseconds: 30);

  ResultTab _tab = ResultTab.overview;
  late final AnimationController _entrance = AnimationController(vsync: this);
  late final List<CurvedAnimation> _blockEntrances = [
    for (var i = 0; i < _risingBlocks; i++)
      CurvedAnimation(
        parent: _entrance,
        curve: Interval(
          _fractionOfEntrance(_blockStagger * i),
          _fractionOfEntrance(_blockStagger * i + AppMotion.base),
          curve: AppMotion.standardDecelerate,
        ),
      ),
  ];
  bool _entranceStarted = false;

  static Duration get _entranceLength =>
      AppMotion.base + _blockStagger * (_risingBlocks - 1);

  static double _fractionOfEntrance(Duration at) =>
      at.inMicroseconds / _entranceLength.inMicroseconds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    // Each block rises over `base`, 30 ms after the one above it
    // (redesign v11 §6.4); reduced motion caps the whole entrance.
    _entrance.duration = AppMotion.durationOf(context, _entranceLength);
    _entrance.forward();
  }

  @override
  void dispose() {
    for (final animation in _blockEntrances) {
      animation.dispose();
    }
    _entrance.dispose();
    super.dispose();
  }

  /// Asks for the labels and writes them, then re-reads the record; a failed
  /// write says so and leaves the labels as they were (SPEC 0149).
  Future<void> _editLabels() async {
    final record = widget.record;
    final labels = await showLabelsDialog(context, record);
    if (labels == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(soilRecordRepositoryProvider)
          .updateLabels(
            widget.recordId,
            fieldName: labels.fieldName,
            sampleLabel: labels.sampleLabel,
          );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível salvar a identificação.'),
        ),
      );
      return;
    }
    if (mounted) ref.invalidate(soilRecordByIdProvider(widget.recordId));
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final details = _DetailsTab(record: record, onEditLabels: _editLabels);
    final classified = record.hasClassification;

    final List<Widget> blocks = classified
        ? [
            ClassificationHeader(record: record),
            SegmentedControl<ResultTab>(
              semanticLabel: 'Seções do resultado',
              value: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
              options: const [
                SegmentedControlOption(
                  value: ResultTab.overview,
                  label: AppStrings.resultTabOverview,
                ),
                SegmentedControlOption(
                  value: ResultTab.management,
                  label: AppStrings.resultTabManagement,
                ),
                SegmentedControlOption(
                  value: ResultTab.details,
                  label: AppStrings.resultTabDetails,
                ),
              ],
            ),
            // Every tab stays mounted, so a tab change cannot drop state such
            // as tips still generating; a hidden tab takes no space.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (tab, content) in [
                  (ResultTab.overview, ResultOverview(record: record)),
                  (ResultTab.management, ManagementTipsSection(record: record)),
                  (ResultTab.details, details),
                ])
                  Visibility(
                    visible: _tab == tab,
                    maintainState: true,
                    child: content,
                  ),
              ],
            ),
          ]
        // Unclassified: why, then the record itself, so it can still be
        // shared and deleted (SPEC 0194).
        : [ResultErrorBlock(cause: record.classificationFailure), details];

    return Scaffold(
      appBar: VisioAppBar(
        title: AppStrings.resultTitle,
        // Reads "Voltar" whatever the locale (SPEC 0118).
        leading: Navigator.canPop(context)
            ? VisioIconButton(
                label: 'Voltar',
                icon: Icons.arrow_back,
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
        // The next sample starts here, in view on the page a save opens
        // (SPEC 0146).
        actions: [
          VisioIconButton(
            label: 'Nova captura',
            icon: Icons.add_a_photo_outlined,
            onPressed: () => context.push('/capture'),
          ),
        ],
      ),
      bottomNavigationBar: classified
          ? _ResultFooter(
              onCorrect: _editLabels,
              onManagementTips: () =>
                  setState(() => _tab = ResultTab.management),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          // The page scrolls under the navigation bar on Android 12 and
          // later (SPEC 0109), so the last action ends above it.
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < blocks.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.lg),
                      _RiseIn(
                        animation: _blockEntrances[i],
                        child: blocks[i],
                      ),
                    ],
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

/// A block of the result's entrance: it fades in and rises 8 px, or only
/// fades under reduced motion (redesign v11 §6.4, §6.5).
class _RiseIn extends StatelessWidget {
  const _RiseIn({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce =
        AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context);
    return FadeTransition(
      key: const ValueKey('result-rise'),
      opacity: animation,
      child: reduce
          ? child
          : AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, 8 * (1 - animation.value)),
                child: child,
              ),
              child: child,
            ),
    );
  }
}

/// [Corrigir] and [Dicas de manejo], side by side, stacked where they no
/// longer fit (redesign v11 §3.6, §8, §10).
class _ResultFooter extends StatelessWidget {
  const _ResultFooter({
    required this.onCorrect,
    required this.onManagementTips,
  });

  final VoidCallback onCorrect;
  final VoidCallback onManagementTips;

  @override
  Widget build(BuildContext context) {
    final stacked = resultStacks(context);
    final correct = VisioButton(
      label: AppStrings.resultCorrect,
      icon: Icons.edit_outlined,
      variant: VisioButtonVariant.secondary,
      onPressed: onCorrect,
    );
    final tips = VisioButton(
      label: AppStrings.resultManagementTips,
      onPressed: onManagementTips,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(
          top: BorderSide(
            color: context.palette.cardBorder,
            width: context.palette.edgeWidth,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    correct,
                    const SizedBox(height: AppSpacing.sm),
                    tips,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: correct),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 2, child: tips),
                  ],
                ),
        ),
      ),
    );
  }
}

// --- Detalhes tab ---

/// The record itself: its photograph, its information and its actions
/// (redesign v11 §3.8 restyles it as v11 item 11).
class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.record, required this.onEditLabels});

  final SoilRecord record;
  final VoidCallback onEditLabels;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SamplePhoto(record: record),
        const SizedBox(height: AppSpacing.lg),
        InfoSection(record: record, onEditLabels: onEditLabels),
        const SizedBox(height: AppSpacing.xl),
        _ActionButtons(record: record),
      ],
    );
  }
}

class _SamplePhoto extends StatelessWidget {
  const _SamplePhoto({required this.record});

  final SoilRecord record;

  static const double _height = 240;

  @override
  Widget build(BuildContext context) {
    final cacheH = (_height * MediaQuery.devicePixelRatioOf(context)).round();

    return ClipRRect(
      borderRadius: AppRadius.borderRadiusLg,
      child: SizedBox(
        height: _height,
        // A labelled button that opens the full-screen viewer, its ink on a
        // transparent Material over the photograph (SPEC 0125).
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The soil sample once it is cut, the photograph until then and
            // when there is none (SPEC 0172).
            Consumer(
              builder: (context, ref, photo) {
                final sample = ref
                    .watch(soilSampleProvider(record.imagePath))
                    .value;
                if (sample == null) return photo!;
                return Image.memory(
                  sample,
                  key: const ValueKey('soil-sample'),
                  fit: BoxFit.cover,
                  cacheHeight: cacheH,
                );
              },
              child: Image.file(
                File(record.imagePath),
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
