import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

/// The result's underlined tabs (redesign v11 PNG 14, SPEC 0202): the labels
/// side by side from the start, 14 sp Inter 500 with 12 dp padding each
/// side, the selected one in `primaryText` over a 3 dp indicator as wide as
/// its label, all over a 1 dp rule across the screen.
class ResultTabBar<T> extends StatelessWidget {
  const ResultTabBar({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<(T, String)> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500);
    return Semantics(
      container: true,
      label: semanticLabel,
      // The indicator sits on the rule, its bottom on the rule's (PNG 14,
      // SPEC 0210).
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: palette.isSun ? 2 : 1,
            child: ColoredBox(
              key: const ValueKey('result-tab-rule'),
              color: palette.isSun
                  ? palette.onSurface
                  : palette.surfaceContainerHigh,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (tab, label) in tabs)
                  _Tab(
                    label: label,
                    selected: tab == value,
                    style: style,
                    onTap: () {
                      if (tab == value) return;
                      unawaited(AppHaptics.selection());
                      onChanged(tab);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The density's target, 56 dp in Modo Sol; the extra height goes above
    // the label so the indicator stays on the rule (review of #436).
    final target = context.density.tap;
    return Semantics(
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: target),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 12 + target - 48),
                  Text(
                    label,
                    maxLines: 1,
                    style: style?.copyWith(
                      color: selected
                          ? palette.primaryText
                          : palette.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 11),
                  Container(
                    key: selected
                        ? const ValueKey('result-tab-indicator')
                        : null,
                    height: 3,
                    decoration: BoxDecoration(
                      color: selected ? palette.primaryText : null,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
