import 'package:flutter/material.dart';

/// Standardized VisioSoil icon-only button (SPEC 0131).
///
/// [label] is required and refused when empty, so an icon-only control can
/// never reach a screen reader nameless (`05-design-system.md` §4.3). It is
/// the button's tooltip, which Flutter reads as its semantic label.
class VisioIconButton extends StatelessWidget {
  // Not const: the assert calls trim(), which a const constructor cannot.
  VisioIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.iconSize,
    this.overPhoto = false,
  }) : assert(label.trim().isNotEmpty, 'VisioIconButton needs a label');

  /// What the button does, in pt-BR: its tooltip and its semantic label.
  final String label;

  final IconData icon;

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// The icon's colour; white when [overPhoto].
  final Color? color;

  final double? iconSize;

  /// Draws the button over a photograph: a white icon on a dark scrim that
  /// reads over any image (SPEC 0107).
  final bool overPhoto;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      color: overPhoto ? Colors.white : color,
      style: overPhoto
          ? IconButton.styleFrom(backgroundColor: Colors.black45)
          : null,
    );
  }
}
