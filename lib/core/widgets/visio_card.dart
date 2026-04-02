import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Card padronizado do VisioSoil.
class VisioCard extends StatelessWidget {
  const VisioCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
  });

  /// Conteúdo do card.
  final Widget child;

  /// Callback opcional ao tocar no card.
  final VoidCallback? onTap;

  /// Padding interno. Padrão: AppSpacing.lg em todos os lados.
  final EdgeInsetsGeometry? padding;

  /// Margem externa.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin ?? EdgeInsets.zero,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }

    return card;
  }
}
