import 'package:flutter/material.dart';

/// VisioButton variants.
enum VisioButtonVariant { primary, secondary }

/// Standardized VisioSoil button.
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

  /// Button text.
  final String label;

  /// Callback when pressed.
  final VoidCallback? onPressed;

  /// Optional icon to the left of the label.
  final IconData? icon;

  /// If true, shows a loading indicator instead of the content.
  final bool isLoading;

  /// Visual variant: primary (filled) or secondary (outlined).
  final VisioButtonVariant variant;

  /// If true, expands to fill all available width.
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
