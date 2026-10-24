import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// A single stat card (redesign v11 §4 `StatCell`): a bold [value] over a
/// [label], with an optional leading [icon] in [color]. Renders a shimmering
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
  }) : isSkeleton = false;

  /// A placeholder [StatCell] shown while the value it would show is still
  /// loading.
  const StatCell.skeleton({super.key})
      : value = '',
        label = '',
        icon = null,
        color = null,
        semanticLabel = null,
        isSkeleton = true;

  final String value;
  final String label;
  final IconData? icon;
  final Color? color;
  final String? semanticLabel;
  final bool isSkeleton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: palette.shadowCard,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: palette.cardBorder, width: palette.edgeWidth),
      ),
      child: isSkeleton ? const _StatCellSkeletonContent() : _buildContent(theme, palette),
    );
  }

  Widget _buildContent(ThemeData theme, AppPalette palette) {
    return Semantics(
      label: semanticLabel ?? '$value $label',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color ?? palette.primary),
              const SizedBox(height: 2),
            ],
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
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
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: cells[i]),
        ],
      ],
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
  late final Animation<double> _opacity =
      _controller.drive(Tween(begin: 0.3, end: 0.6));

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
