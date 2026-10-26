import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

/// A single stat card (redesign v11 §4 `StatCell`, PNG 08 as SPEC 0203
/// measures it): an optional 20 dp [icon] in [color], then a 24 sp [value]
/// over a 12 sp [label]. Renders a shimmering
/// placeholder instead when [isSkeleton].
///
/// [semanticLabel] overrides the default `"<value> <label>"` reading, for a
/// caller whose label alone does not make a full sentence (e.g. "6 análises
/// nesta semana", redesign v11 §8).
class StatCell extends StatelessWidget {
  const StatCell({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.semanticLabel,
    this.valueStyle,
    this.labelStyle,
  }) : isSkeleton = false;

  /// A placeholder [StatCell] shown while the value it would show is still
  /// loading.
  const StatCell.skeleton({super.key})
    : value = '',
      label = '',
      icon = null,
      color = null,
      semanticLabel = null,
      valueStyle = null,
      labelStyle = null,
      isSkeleton = true;

  final String value;
  final String label;
  final IconData? icon;
  final Color? color;
  final String? semanticLabel;
  final bool isSkeleton;
  final TextStyle? valueStyle;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    // Flat on `surface`, its content centred in the row's height (PNG 08,
    // SPEC 0203); only Modo Sol draws an edge.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.borderRadiusLg,
        border: palette.highContrast
            ? Border.all(color: palette.cardBorder, width: palette.edgeWidth)
            : null,
      ),
      child: isSkeleton
          ? const _StatCellSkeletonContent()
          : _buildContent(theme, palette),
    );
  }

  Widget _buildContent(ThemeData theme, AppPalette palette) {
    return Semantics(
      label: semanticLabel ?? '$value $label',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // An 18 dp icon 2 dp lower, so the value keeps its place
            // (PNG 08, SPEC 0210).
            if (icon != null) ...[
              const SizedBox(height: 2),
              Icon(icon, size: 18, color: color ?? palette.onSurface),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              value,
              style:
                  valueStyle ??
                  AppTypography.tabular(
                    AppTypography.weighted(
                      theme.textTheme.headlineMedium!.copyWith(
                        fontSize: 24,
                        height: 32 / 24,
                        letterSpacing: -0.6,
                      ),
                      650,
                    ),
                  ),
            ),
            Text(
              label,
              style:
                  labelStyle ??
                  theme.textTheme.bodySmall?.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays [cells] out in an equal-width row with the design system's spacing
/// between them (redesign v11 §4 `StatsRow`).
class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.cells});

  final List<StatCell> cells;

  @override
  Widget build(BuildContext context) {
    // Every card takes the tallest one's height (PNG 08, SPEC 0203).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }
}

/// Shimmering bars standing in for the icon, value and label while a
/// [StatCell] is a skeleton (redesign v11 §6.4: a 1.2 s loop, off under
/// reduced motion).
class _StatCellSkeletonContent extends StatefulWidget {
  const _StatCellSkeletonContent();

  @override
  State<_StatCellSkeletonContent> createState() =>
      _StatCellSkeletonContentState();
}

class _StatCellSkeletonContentState extends State<_StatCellSkeletonContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  late final Animation<double> _opacity = _controller.drive(
    Tween(begin: 0.3, end: 0.6),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.palette.surfaceContainerHigh;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.borderRadiusXs,
      ),
    );

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Opacity(
          opacity: _reduceMotion ? 0.45 : _opacity.value,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(14, 14),
              const SizedBox(height: 6),
              bar(32, 20),
              const SizedBox(height: 4),
              bar(48, 12),
            ],
          ),
        ),
      ),
    );
  }
}
