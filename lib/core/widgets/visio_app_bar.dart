import 'package:flutter/material.dart';

/// Standardized VisioSoil AppBar.
class VisioAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VisioAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.centerTitle = true,
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

  /// Whether to center the title. Default: true.
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: titleWidget ?? (title != null ? Text(title!) : null),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
