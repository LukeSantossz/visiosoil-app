import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

/// The row Configurações and Perfil list (PNG 21 and 23, SPEC 0204): a
/// 22 dp icon, a 15 sp title over a 13 sp line, and a chevron when it opens
/// something. [trailing] replaces the chevron.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleMaxLines,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int? subtitleMaxLines;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Draws the icon and the title in `error`.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final trailing = this.trailing;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: SettingsRowFrame(
          icon: Icon(
            icon,
            size: 22,
            color: destructive ? palette.error : palette.primaryText,
          ),
          title: title,
          titleColor: destructive ? palette.error : null,
          subtitle: subtitle,
          subtitleMaxLines: subtitleMaxLines,
          trailing:
              trailing ??
              (onTap == null
                  ? null
                  : Icon(
                      LucideIcons.chevronRight,
                      size: 20,
                      color: palette.textTertiary,
                    )),
        ),
      ),
    );
  }
}

/// The layout every settings row shares, a switch's included: at least
/// 56 dp tall, 16 dp in, the text 12 dp after the icon (SPEC 0204).
class SettingsRowFrame extends StatelessWidget {
  const SettingsRowFrame({
    super.key,
    this.icon,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.subtitleMaxLines,
    this.trailing,
  });

  final Widget? icon;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final int? subtitleMaxLines;
  final Widget? trailing;

  /// The 15 sp title and the 13 sp line under it.
  static TextStyle titleStyle(BuildContext context) => AppTypography.resized(
    Theme.of(context).textTheme.bodyMedium!,
    15,
    height: 20 / 15,
  ).copyWith(fontWeight: FontWeight.w500, color: context.palette.onSurface);

  static TextStyle subtitleStyle(BuildContext context) => AppTypography.resized(
    Theme.of(context).textTheme.bodySmall!,
    13,
    height: 18 / 13,
  ).copyWith(color: context.palette.onSurfaceVariant);

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: context.palette.isSun ? 64 : 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        // The trailing control takes what it needs, up to three quarters of
        // the row; the text takes the rest.
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: titleStyle(context).copyWith(color: titleColor),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: subtitleMaxLines,
                        softWrap: subtitleMaxLines == 1 ? false : null,
                        overflow: subtitleMaxLines == null
                            ? null
                            : TextOverflow.ellipsis,
                        style: subtitleStyle(context),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.md),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.75,
                  ),
                  child: trailing,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A flat `surface` card of settings rows with full-width rules between
/// them; only Modo Sol draws its edge (SPEC 0204).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      key: const Key('settings-group'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: palette.highContrast
            ? Border.all(color: palette.cardBorder, width: palette.edgeWidth)
            : null,
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index != 0)
              Divider(
                height: palette.edgeWidth,
                thickness: palette.edgeWidth,
                color: palette.divider,
              ),
            children[index],
          ],
        ],
      ),
    );
  }
}
