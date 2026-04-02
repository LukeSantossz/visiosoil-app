import 'package:flutter/material.dart';

/// Variantes do VisioButton.
enum VisioButtonVariant { primary, secondary }

/// Botão padronizado do VisioSoil.
class VisioButton extends StatelessWidget {
  const VisioButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = VisioButtonVariant.primary,
    this.expanded = false,
  });

  /// Texto do botão.
  final String label;

  /// Callback ao pressionar.
  final VoidCallback? onPressed;

  /// Ícone opcional à esquerda do label.
  final IconData? icon;

  /// Se true, mostra loading indicator em vez do conteúdo.
  final bool isLoading;

  /// Variante visual: primary (filled) ou secondary (outlined).
  final VisioButtonVariant variant;

  /// Se true, expande para ocupar toda a largura disponível.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild(context);

    Widget button;
    if (variant == VisioButtonVariant.primary) {
      button = ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        child: child,
      );
    } else {
      button = OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        child: child,
      );
    }

    if (expanded) {
      return SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }

  Widget _buildChild(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            variant == VisioButtonVariant.primary
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    }

    return Text(label);
  }
}
