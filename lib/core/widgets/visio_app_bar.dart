import 'package:flutter/material.dart';

/// Standardized VisioSoil AppBar.
class VisioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VisioAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.backgroundColor,
  }) : assert(
         title == null || titleWidget == null,
         'Não é possível usar title e titleWidget ao mesmo tempo',
       );

  /// Title as a String.
  final String? title;

  /// Title as a custom Widget.
  final Widget? titleWidget;

  /// Widget on the left (e.g. back button).
  final Widget? leading;

  /// Widgets on the right.
  final List<Widget>? actions;

  /// Overrides the theme's; a [WidgetStateColor] can resolve differently
  /// when content scrolls under the bar.
  final Color? backgroundColor;

  /// Whether to center the title. Default: false, start-aligned as in the
  /// redesign mocks (SPEC 0201).
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    // The mocks set the title 60 dp from the edge after the back arrow and
    // 16 dp without one (SPEC 0201).
    final hasLeading =
        leading != null ||
        (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
    return AppBar(
      title: titleWidget ?? (title != null ? Text(title!) : null),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      titleSpacing: centerTitle ? null : (hasLeading ? 4 : 16),
      backgroundColor: backgroundColor,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}
