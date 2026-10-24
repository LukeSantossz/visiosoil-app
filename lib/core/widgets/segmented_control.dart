import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// One choice in a [SegmentedControl].
class SegmentedControlOption<T> {
  const SegmentedControlOption({required this.value, required this.label, this.icon});

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
  });

  final List<SegmentedControlOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Describes the group for a screen reader (e.g. "Visualização"). Optional:
  /// each segment already names itself.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selectedIndex = options.indexWhere((o) => o.value == value);
    final height = context.density.tap;

    return Semantics(
      container: true,
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / options.length;

          return Container(
            height: height,
            // The clip shape comes from a borderless `decoration` (clipping
            // needs one); the border itself is a `foregroundDecoration`. A
            // *background* decoration's border would otherwise reserve
            // padding equal to its width, shrinking every segment's tap
            // target below the 48 dp floor (redesign v11 §8).
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusPill,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusPill,
              border: Border.all(color: palette.outline, width: palette.edgeWidth),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (selectedIndex >= 0)
                  AnimatedPositioned(
                    duration: AppMotion.durationOf(context, AppMotion.base),
                    curve: AppMotion.standard,
                    left: segmentWidth * selectedIndex,
                    top: 0,
                    bottom: 0,
                    width: segmentWidth,
                    child: Container(color: palette.isSun ? Colors.black : palette.selected),
                  ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < options.length; i++)
                        Expanded(child: _buildSegment(context, i)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSegment(BuildContext context, int index) {
    final option = options[index];
    final isSelected = option.value == value;
    final foreground = context.palette.isSun && isSelected ? Colors.white : null;

    void select() {
      if (!isSelected) {
        AppHaptics.selection();
        onChanged(option.value);
      }
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: option.label,
      onTap: select,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: select,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.icon != null) ...[
                  Icon(option.icon, size: 16, color: foreground),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  option.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
