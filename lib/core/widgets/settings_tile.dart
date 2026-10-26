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
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int? subtitleMaxLines;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Draws the icon and the title in `error`.
  final bool destructive;

  /// False greys the title and the line, as PNG 23 draws a row that needs a
  /// linked account; the icon keeps its colour (SPEC 0216).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final trailing = this.trailing;
    final onTap = enabled ? this.onTap : null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: SettingsRowFrame(
          icon: Icon(
            icon,
            size: SettingsRowFrame.iconSize,
            color: destructive
                ? palette.error
                : SettingsRowFrame.iconColor(context),
          ),
          title: title,
          titleColor: destructive ? palette.error : null,
          subtitle: subtitle,
          subtitleMaxLines: subtitleMaxLines,
          dimmed: !enabled,
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
/// 56 dp tall counting the rule above it, 16 dp in, the text 12 dp after the
/// icon (SPEC 0204, SPEC 0215).
class SettingsRowFrame extends StatelessWidget {
  const SettingsRowFrame({
    super.key,
    this.icon,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.subtitleMaxLines,
    this.trailing,
    this.dimmed = false,
  });

  final Widget? icon;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final int? subtitleMaxLines;
  final Widget? trailing;

  /// Draws the title and the line at 55 %, as PNG 23 greys an unavailable
  /// row (SPEC 0216).
  final bool dimmed;

  /// A row's icon: 20 dp at the start of a 22 dp slot, so the text keeps its
  /// place (PNG 23, 35 and 36, SPEC 0216).
  static const double iconSize = 20;
  static const double _iconSlot = 22;

  /// The 15 sp title, 17 sp in Modo Sol (PNG 36), and the 13 sp line under
  /// it.
  static TextStyle titleStyle(BuildContext context) {
    final size = context.palette.isSun ? 17.0 : 15.0;
    return AppTypography.resized(
      Theme.of(context).textTheme.bodyMedium!,
      size,
      height: 20 / size,
    ).copyWith(fontWeight: FontWeight.w500, color: context.palette.onSurface);
  }

  /// `primaryText`, or ink in Modo Sol, which draws every line in ink
  /// (PNG 36).
  static Color iconColor(BuildContext context) => context.palette.isSun
      ? context.palette.onSurface
      : context.palette.primaryText;

  static TextStyle subtitleStyle(BuildContext context) => AppTypography.resized(
    Theme.of(context).textTheme.bodySmall!,
    13,
    height: 18 / 13,
  ).copyWith(color: context.palette.onSurfaceVariant);

  Color _dim(Color color) => dimmed ? color.withValues(alpha: 0.55) : color;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    // PNG 35 and 36 draw the rule above a row inside its 56 dp, so the row
    // starts its content under the rule and keeps the whole 56 dp target.
    final rule =
        context.dependOnInheritedWidgetOfExactType<_RuleAbove>()?.width ?? 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.lg, rule, AppSpacing.lg, 0),
        // The trailing control takes what it needs, up to three quarters of
        // the row; the text takes the rest.
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (icon != null) ...[
                SizedBox(
                  width: _iconSlot,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    child: icon,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              // Only the text is padded; a control is centred in the row's
              // full height, so its own target is not padded again.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: titleStyle(context).copyWith(
                          color: _dim(titleColor ?? context.palette.onSurface),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: subtitleMaxLines,
                          softWrap: subtitleMaxLines == 1 ? false : null,
                          overflow: subtitleMaxLines == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: subtitleStyle(context).copyWith(
                            color: _dim(context.palette.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
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
          for (var index = 0; index < children.length; index++)
            if (index == 0)
              children[index]
            else
              // The rule lies over the top of the row, which leaves room for
              // it (PNG 35 and 36, SPEC 0215).
              Stack(
                children: [
                  _RuleAbove(width: palette.edgeWidth, child: children[index]),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Divider(
                      key: const Key('settings-rule'),
                      height: palette.edgeWidth,
                      thickness: palette.edgeWidth,
                      color: palette.divider,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// The width of the rule [SettingsGroup] draws over the top of a row, which
/// the row leaves room for (SPEC 0215).
class _RuleAbove extends InheritedWidget {
  const _RuleAbove({required this.width, required super.child});

  final double width;

  @override
  bool updateShouldNotify(_RuleAbove oldWidget) => oldWidget.width != width;
}
