import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_capture_card.dart';
import 'package:visiosoil_app/core/features/home/widgets/home_data_error.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/main_tab_index_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(soilRecordsStreamProvider);
    final recordsAsync = source.whenData(
      (records) => [...records]
        ..sort(
          (a, b) => (DateTime.tryParse(b.timestamp) ?? DateTime(0)).compareTo(
            DateTime.tryParse(a.timestamp) ?? DateTime(0),
          ),
        ),
    );
    final records = recordsAsync.value ?? [];
    final offline =
        ref.watch(connectivityStatusProvider).value ==
        ConnectivityStatus.offline;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg + AppSpacing.xs),
          child: CustomPaint(
            painter: context.density.borderWidth == 2
                ? null
                : _HomeContours(
                    context.palette.primaryText.withValues(alpha: .10),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Início',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                    ),
                    // Transitional until the Perfil tab hosts Settings (SPEC §3.13 / item 6).
                    VisioIconButton(
                      label: 'Configurações',
                      icon: Icons.settings_outlined,
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                HeroCaptureCard(onCapture: () => context.push('/capture')),
                const SizedBox(height: AppSpacing.xl),
                if (source.hasError)
                  HomeDataError(
                    onRetry: () => ref.invalidate(soilRecordsStreamProvider),
                  )
                else ...[
                  Semantics(
                    header: true,
                    child: Text(
                      'Esta semana',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  StatsGrid(recordsAsync: recordsAsync),
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.md,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Recentes',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      if (records.isNotEmpty)
                        VisioButton(
                          label: 'Ver todas',
                          variant: VisioButtonVariant.text,
                          onPressed: () =>
                              ref.read(mainTabIndexProvider.notifier).select(1),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: AppRadius.borderRadiusLg,
                      border: context.density.borderWidth == 2
                          ? Border.all(
                              color: context.palette.outline,
                              width: context.density.borderWidth,
                            )
                          : null,
                    ),
                    child: recordsAsync.isLoading
                        ? const _RecentSkeleton()
                        : records.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xxxl,
                              horizontal: AppSpacing.lg,
                            ),
                            child: Column(
                              children: [
                                ExcludeSemantics(
                                  child: CustomPaint(
                                    size: const Size(110, 90),
                                    painter: _EmptySoilIllustration(
                                      context.palette.primaryText,
                                      context.palette.primaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                Text(
                                  'Suas análises aparecem aqui.',
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Fotografe a camada de 0–20 cm, na sombra e sem palha.',
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              for (
                                var index = 0;
                                index < records.length && index < 5;
                                index++
                              ) ...[
                                if (index > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 76,
                                      right: AppSpacing.lg,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: context.palette.divider,
                                    ),
                                  ),
                                AnalysisTile(
                                  record: records[index],
                                  dense: true,
                                  showSyncStatus: true,
                                  offline: offline,
                                  onTap: () => context.push(
                                    '/details',
                                    extra: records[index].id,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSkeleton extends StatefulWidget {
  const _RecentSkeleton();
  @override
  State<_RecentSkeleton> createState() => _RecentSkeletonState();
}

class _RecentSkeletonState extends State<_RecentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _reduce = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (_reduce) {
      _controller.stop();
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, child) => Opacity(
      opacity: _reduce ? .45 : .3 + .3 * _controller.value,
      child: child,
    ),
    child: const Column(
      children: [
        AnalysisTileSkeleton(),
        AnalysisTileSkeleton(),
        AnalysisTileSkeleton(),
      ],
    ),
  );
}

/// Contour lines are decorative and disappear in Sun mode.
class _HomeContours extends CustomPainter {
  const _HomeContours(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & Size(size.width, 270));
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = 0; index < 9; index++) {
      final inset = index * 19.0;
      final path = Path()
        ..moveTo(size.width * .72 - inset, -40)
        ..cubicTo(
          size.width * .4 - inset,
          45,
          size.width * .9 - inset,
          100 + inset,
          size.width * .7 - inset,
          135 + inset,
        )
        ..cubicTo(
          size.width * .35 - inset,
          185 + inset,
          size.width * .95,
          205 + inset,
          size.width + 30,
          155 + inset,
        );
      canvas.drawPath(path, pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HomeContours oldDelegate) => color != oldDelegate.color;
}

class _EmptySoilIllustration extends CustomPainter {
  const _EmptySoilIllustration(this.ink, this.fill);
  final Color ink;
  final Color fill;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const center = Offset(49, 30);
    canvas.drawCircle(center, 23, Paint()..color = fill);
    canvas.drawCircle(center, 23, pen);
    canvas.drawLine(const Offset(66, 47), const Offset(84, 65), pen);
    for (final grain in [
      const Offset(42, 25),
      const Offset(55, 28),
      const Offset(47, 37),
      const Offset(58, 38),
    ]) {
      canvas.drawCircle(grain, 1.8, Paint()..color = ink);
    }
    for (final y in [77.0, 87.0]) {
      final soil = Path()
        ..moveTo(5, y)
        ..cubicTo(30, y - 7, 42, y + 5, 65, y - 1)
        ..cubicTo(85, y - 8, 96, y - 5, 108, y);
      canvas.drawPath(soil, pen);
    }
  }

  @override
  bool shouldRepaint(_EmptySoilIllustration oldDelegate) =>
      ink != oldDelegate.ink || fill != oldDelegate.fill;
}
