import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

/// One choice in a [SegmentedControl].
class SegmentedControlOption<T> {
  const SegmentedControlOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// A pill-shaped segmented control (redesign v11 §4): an indicator that
/// slides to the selected [options] entry over [AppMotion.base] (closest
/// named token to the mock's 250 ms). Plays [AppHaptics.selection] when the
/// selection actually changes (redesign v11 §7).
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.compact = false,
  });

  final List<SegmentedControlOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Describes the group for a screen reader (e.g. "Visualização"). Optional:
  /// each segment already names itself.
  final String? semanticLabel;

  /// A pill sized to its labels, for the end of a settings row: 32 dp, or
  /// 44 dp in Modo Sol, each segment its own label's width (PNG 35 and 36,
  /// SPEC 0215).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selectedIndex = options.indexWhere((o) => o.value == value);
    // The mock draws a 40 dp pill (PNG 16, SPEC 0203). Its hit area keeps
    // the 48 dp floor by reaching 8 dp below it, into the gap the mock leaves;
    // Modo Sol draws the pill at its 56 dp target.
    final target = context.density.tap;
    final pillHeight = compact
        ? (palette.isSun ? 44.0 : 32.0)
        : palette.isSun
        ? target
        : 40.0;
    // A compact pill reaches 8 dp above and below, centred in its row: 48 dp
    // in light, 60 dp in Modo Sol, each at least its target (SPEC 0215).
    final padding = compact
        ? const EdgeInsets.symmetric(vertical: AppSpacing.sm)
        : EdgeInsets.only(bottom: target - pillHeight);

    return Semantics(
      container: true,
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A compact control wider than its room shrinks its segments, so
          // the indicator and rules stay on the labels (review of #438).
          final natural = compact
              ? _compactSegmentWidths(context)
              : List.filled(
                  options.length,
                  constraints.maxWidth / options.length,
                );
          final total = natural.fold(0.0, (sum, width) => sum + width);
          final widths = total > constraints.maxWidth
              ? [for (final w in natural) w * constraints.maxWidth / total]
              : natural;
          double startOf(int index) =>
              widths.take(index).fold(0.0, (sum, width) => sum + width);

          final control = Stack(
            children: [
              Padding(
                padding: padding,
                child: IntrinsicHeight(
                  child: Container(
                    key: const Key('segmented-pill'),
                    constraints: BoxConstraints(minHeight: pillHeight),
                    // The clip shape comes from a borderless `decoration`; the
                    // border is a `foregroundDecoration`, so it reserves no
                    // padding inside the pill.
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.borderRadiusPill,
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: AppRadius.borderRadiusPill,
                      border: Border.all(
                        color: palette.outline,
                        width: palette.edgeWidth,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        if (selectedIndex >= 0)
                          AnimatedPositioned(
                            duration: AppMotion.durationOf(
                              context,
                              AppMotion.base,
                            ),
                            curve: AppMotion.standard,
                            left: startOf(selectedIndex),
                            top: 0,
                            bottom: 0,
                            width: widths[selectedIndex],
                            child: Container(
                              color: palette.isSun
                                  ? Colors.black
                                  : palette.selected,
                            ),
                          ),
                        // A rule between segments (PNG 16 and 23).
                        for (var i = 1; i < options.length; i++)
                          Positioned(
                            left: startOf(i) - palette.edgeWidth / 2,
                            top: 0,
                            bottom: 0,
                            width: palette.edgeWidth,
                            child: ColoredBox(
                              key: const Key('segment-separator'),
                              color: palette.outline,
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < options.length; i++)
                              SizedBox(
                                width: widths[i],
                                child: _buildLabel(context, i),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (var i = 0; i < options.length; i++)
                      SizedBox(width: widths[i], child: _buildTarget(i)),
                  ],
                ),
              ),
            ],
          );
          return compact
              ? SizedBox(width: startOf(options.length), child: control)
              : control;
        },
      ),
    );
  }

  TextStyle? _labelStyle(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall!;
    if (!compact) return style.copyWith(fontWeight: FontWeight.w500);
    // 12.5 sp at weight 500, or 14.5 sp at weight 600 in Modo Sol (PNG 35
    // and 36, SPEC 0215).
    final sun = context.palette.isSun;
    return AppTypography.weighted(
      AppTypography.resized(style, sun ? 14.5 : 12.5),
      sun ? 600 : 500,
    );
  }

  /// Each label's width, 13 dp either side of it (PNG 35 and 36).
  List<double> _compactSegmentWidths(BuildContext context) => [
    for (final option in options) _labelWidth(context, option.label) + 26,
  ];

  double _labelWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  Widget _buildTarget(int index) {
    final option = options[index];
    final isSelected = option.value == value;

    void select() {
      if (!isSelected) {
        AppHaptics.selection();
        onChanged(option.value);
      }
    }

    return Semantics(
      key: Key('segment-$index'),
      container: true,
      button: true,
      selected: isSelected,
      label: option.label,
      onTap: select,
      // An InkWell, so a keyboard or D-pad can focus the segment and Enter
      // selects it. Its press ink is off: it would spread over the hit area,
      // which runs past the pill (review of #437).
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          excludeFromSemantics: true,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: select,
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, int index) {
    final option = options[index];
    final isSelected = option.value == value;
    final color = context.palette.isSun && isSelected
        ? Colors.white
        : context.palette.onSurface;

    // A 20 dp icon and the 14 sp label (PNG 16, SPEC 0203).
    return ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.all(compact ? 0 : AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (option.icon != null) ...[
              Icon(option.icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.sm),
            ],
            // One line, scaled down rather than clipped when a word
            // cannot fit its segment (SPEC 0197).
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  option.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: _labelStyle(context)?.copyWith(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
