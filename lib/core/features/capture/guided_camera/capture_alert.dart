import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// The failed chip snapshot remains legible for the full warning interval.
class CaptureAlert extends StatelessWidget {
  const CaptureAlert({super.key, required this.failures});
  static const visibleDuration = Duration(milliseconds: 3800);
  final Map<String, String> failures;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final reasons = failures.keys.join(', ');
    final corrections = failures.values.toSet().join(', ');
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('capture-alert'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.warningContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: palette.isSun
              ? Border.all(color: palette.outline, width: 2)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: palette.onWarningContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: palette.onWarningContainer),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ainda não dá para fotografar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text('$reasons. $corrections.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
