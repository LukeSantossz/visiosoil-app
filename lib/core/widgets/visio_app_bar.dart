import 'package:flutter/material.dart';

/// AppBar padronizada do VisioSoil.
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

  /// Título como String.
  final String? title;

  /// Título como Widget customizado.
  final Widget? titleWidget;

  /// Widget à esquerda (ex: botão voltar).
  final Widget? leading;

  /// Widgets à direita.
  final List<Widget>? actions;

  /// Centralizar título. Padrão: true.
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
