import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/data/sync/sync_availability.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_capture_card.dart';
import 'package:visiosoil_app/core/features/home/widgets/home_data_error.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
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
    // On surfaceContainer, so the white cards stand out; Modo Sol stays
    // white (PNG 08, 25 and 27, SPEC 0203).
    return Scaffold(
      backgroundColor: context.palette.highContrast
          ? context.palette.background
          : context.palette.surfaceContainer,
      body: SafeArea(
        child: SingleChildScrollView(
          // Blocks 16 dp from the edge, titles 20 dp (PNG 08).
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg + AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          // Centred at most 560 dp wide on a tablet (redesign v11 §10).
          child: Center(
            child: ConstrainedBox(
              key: const Key('homeContent'),
              constraints: const BoxConstraints(maxWidth: 560),
              child: CustomPaint(
                painter: context.density.borderWidth == 2
                    ? null
                    : _HomeContours(
                        context.palette.primaryText.withValues(alpha: .10),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The title alone, 20 dp in (PNG 08, SPEC 0203): Perfil
                    // hosts Settings, and the mock draws no logo.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Início',
                          style: AppTypography.pageTitle(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    HeroCaptureCard(onCapture: () => context.push('/capture')),
                    const SizedBox(height: 28),
                    if (source.hasError)
                      HomeDataError(
                        onRetry: () =>
                            ref.invalidate(soilRecordsStreamProvider),
                      )
                    else ...[
                      _SectionTitle('Esta semana'),
                      const SizedBox(height: AppSpacing.md),
                      StatsGrid(
                        recordsAsync: recordsAsync,
                        collectionClasses: ref
                            .watch(contractClassesProvider)
                            .value,
                      ),
                      // The link's 48 dp target centres the title in it, so
                      // the gaps give back its 12 dp above and below; its
                      // text ends 4 dp from the card's edge (PNG 08).
                      SizedBox(height: records.isNotEmpty ? 16 : 28),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.md,
                        children: [
                          const _SectionTitle('Recentes'),
                          if (records.isNotEmpty)
                            Transform.translate(
                              offset: const Offset(AppSpacing.sm, 0),
                              child: VisioButton(
                                label: 'Ver todas',
                                variant: VisioButtonVariant.text,
                                // 14 sp, in ink in Modo Sol (PNG 25,
                                // SPEC 0213).
                                // 48 dp, Material's least target, in Modo
                                // Sol too: its 56 dp would push "Recentes"
                                // and the list 4 and 8 dp down (PNG 25).
                                style: const ButtonStyle(
                                  minimumSize: WidgetStatePropertyAll(
                                    Size(64, 48),
                                  ),
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 14,
                                  color: context.palette.isSun
                                      ? context.palette.onSurface
                                      : context.palette.primaryText,
                                ),
                                onPressed: () => ref
                                    .read(mainTabIndexProvider.notifier)
                                    .select(1),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: records.isNotEmpty ? 0 : AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
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
                            // PNG 09: the drawing 48 dp under the card's
                            // top, a 15/20 line and a 13/18 sentence under it
                            // (SPEC 0210).
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  43,
                                  AppSpacing.lg,
                                  17,
                                ),
                                child: Column(
                                  children: [
                                    ExcludeSemantics(
                                      child: CustomPaint(
                                        size: const Size(110, 77),
                                        painter: _EmptySoilIllustration(
                                          context.palette.primaryText,
                                          context.palette.primaryContainer
                                              .withValues(alpha: .55),
                                          context.palette.textTertiary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 25),
                                    Text(
                                      'Suas análises aparecem aqui.',
                                      style: AppTypography.resized(
                                        theme.textTheme.bodyLarge!,
                                        15,
                                        height: 20 / 15,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Fotografe a camada de 0–20 cm, na sombra e sem palha.',
                                      style:
                                          AppTypography.resized(
                                            theme.textTheme.bodyMedium!,
                                            13,
                                            height: 18 / 13,
                                          ).copyWith(
                                            color: context
                                                .palette
                                                .onSurfaceVariant,
                                          ),
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
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                              start: 68,
                                              end: AppSpacing.lg,
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
                                      syncWired: syncBackendWired,
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
        ),
      ),
    );
  }
}

/// A section title 20 dp from the edge, 17 sp weight 600 (PNG 08, SPEC 0203).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: AppTypography.resized(
          Theme.of(context).textTheme.titleMedium!,
          17,
          height: 24 / 17,
        ),
      ),
    ),
  );
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

/// PNG 09's magnifier over two soil lines, at the coordinates measured on
/// the mock (SPEC 0210): a 21 dp lens in `primaryText` over `primaryContainer`
/// at 55 %, three grains, and the lines in `textTertiary`, the lower at half.
class _EmptySoilIllustration extends CustomPainter {
  const _EmptySoilIllustration(this.ink, this.fill, this.line);
  final Color ink;
  final Color fill;
  final Color line;

  static const _upper = [
    Offset(8.25, 65.25),
    Offset(14.25, 64.25),
    Offset(20.25, 63.5),
    Offset(26.25, 63.5),
    Offset(32.25, 64),
    Offset(38.25, 65),
    Offset(44.25, 65.5),
    Offset(50.25, 65.75),
    Offset(56.25, 65.5),
    Offset(62.25, 64.25),
    Offset(68.25, 62.5),
    Offset(74.25, 61.5),
    Offset(80.25, 60.5),
    Offset(86.25, 60.25),
    Offset(92.25, 61),
    Offset(98.25, 62.5),
    Offset(102, 63.25),
  ];

  static const _lower = [
    Offset(16.5, 74.75),
    Offset(20.25, 74.5),
    Offset(26.25, 74),
    Offset(32.25, 73.75),
    Offset(38.25, 74),
    Offset(44.25, 74.5),
    Offset(50.25, 74.5),
    Offset(56.25, 75),
    Offset(62.25, 75),
    Offset(68.25, 74.75),
    Offset(74.25, 74),
    Offset(80.25, 72.75),
    Offset(86.25, 71.75),
    Offset(92.25, 71),
    Offset(98.25, 72),
    Offset(100.5, 72.5),
  ];

  /// A Catmull-Rom curve through [points].
  static Path _smooth(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? 0 : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    Paint pen(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const center = Offset(49.35, 22);
    canvas.drawCircle(center, 21, Paint()..color = fill);
    canvas.drawCircle(center, 21, pen(ink));
    canvas.drawLine(
      const Offset(64.25, 36.9),
      const Offset(80, 52.75),
      pen(ink),
    );
    for (final (grain, radius) in const [
      (Offset(42.25, 18), 3.0),
      (Offset(53.5, 20.5), 2.25),
      (Offset(47.25, 28.25), 1.5),
      (Offset(57.25, 29), 1.0),
    ]) {
      canvas.drawCircle(grain, radius, Paint()..color = ink);
    }
    canvas.drawPath(_smooth(_upper), pen(line));
    canvas.drawPath(_smooth(_lower), pen(line.withValues(alpha: .5)));
  }

  @override
  bool shouldRepaint(_EmptySoilIllustration oldDelegate) =>
      ink != oldDelegate.ink ||
      fill != oldDelegate.fill ||
      line != oldDelegate.line;
}
