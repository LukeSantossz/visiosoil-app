import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

/// The failed chip snapshot remains legible for the full warning interval.
/// Drawn as PNG 12 measures it (SPEC 0211); Modo Sol keeps the theme's
/// warning container under a 2 dp rule.
class CaptureAlert extends StatelessWidget {
  const CaptureAlert({
    super.key,
    required this.causes,
    required this.corrections,
  });
  static const visibleDuration = Duration(milliseconds: 3800);

  /// What is wrong, in the chips' order.
  final List<String> causes;

  /// What to do about it, in the order PNG 12 lists them.
  final List<String> corrections;

  static const _card = Color(0xFFFFF4E2);
  static const _ink = Color(0xFF3A2A10);
  static const _icon = Color(0xFFB26A00);

  /// [items] as a Portuguese list, "a, b e c", opening with a capital.
  static String _sentence(List<String> items) {
    if (items.isEmpty) return '';
    final joined = items.length == 1
        ? items.single
        : '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
    return '${joined[0].toUpperCase()}${joined.substring(1)}.';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sun = palette.isSun;
    final ink = sun ? palette.onWarningContainer : _ink;
    final text = Theme.of(context).textTheme;
    final reasons = causes.join(', ');
    final line = [
      if (reasons.isNotEmpty)
        '${reasons[0].toUpperCase()}${reasons.substring(1)}.',
      if (corrections.isNotEmpty) _sentence(corrections),
    ].join(' ');
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('capture-alert'),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
        decoration: BoxDecoration(
          color: sun ? palette.warningContainer : _card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: sun ? Border.all(color: palette.outline, width: 2) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                LucideIcons.circleAlert,
                size: 20,
                color: sun ? palette.onWarningContainer : _icon,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ainda não dá para fotografar',
                    style: AppTypography.resized(
                      text.titleMedium!,
                      14,
                      height: 19 / 14,
                    ).copyWith(color: ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style: AppTypography.resized(
                      text.bodyMedium!,
                      13,
                      height: 17.5 / 13,
                    ).copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
