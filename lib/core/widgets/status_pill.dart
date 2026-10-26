import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// The three states a [StatusPill] can show (redesign v11 §4): a record sent
/// to the server, one still waiting on a connection, and one whose last sync
/// attempt failed. Decoupled from `SoilRecord.syncStatus`'s raw string, so a
/// caller maps its own status to this enum rather than this widget knowing
/// the sync model.
enum StatusPillStatus {
  sent,
  pending,
  error;

  String get label => switch (this) {
    StatusPillStatus.sent => 'Enviada',
    StatusPillStatus.pending => 'Pendente',
    StatusPillStatus.error => 'Erro',
  };

  IconData get icon => switch (this) {
    StatusPillStatus.sent => LucideIcons.cloudCheck,
    StatusPillStatus.pending => LucideIcons.refreshCw,
    StatusPillStatus.error => LucideIcons.cloudOff,
  };

  Color backgroundColor(AppPalette palette) => switch (this) {
    StatusPillStatus.sent => palette.primaryContainer,
    StatusPillStatus.pending => palette.warningContainer,
    StatusPillStatus.error => palette.errorContainer,
  };

  Color foregroundColor(AppPalette palette) => switch (this) {
    StatusPillStatus.sent => palette.onPrimaryContainer,
    StatusPillStatus.pending => palette.onWarningContainer,
    StatusPillStatus.error => palette.onErrorContainer,
  };
}

/// A small status pill (redesign v11 §4): icon + label in one of three
/// semantic colors, never color alone. Used for a record's sync status
/// (enviada/pendente/erro).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final StatusPillStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      label: status.label,
      child: ExcludeSemantics(
        child: Container(
          constraints: BoxConstraints(minHeight: palette.isSun ? 28 : 24),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: status.backgroundColor(palette),
            border: context.palette.isSun
                ? Border.all(color: Colors.black, width: 2)
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A 16 dp Lucide icon (PNG 16, SPEC 0203).
              Icon(
                status.icon,
                size: 16,
                color: status.foregroundColor(palette),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                status.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: palette.isSun ? 14 : 12,
                  fontWeight: FontWeight.w600,
                  color: status.foregroundColor(palette),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
