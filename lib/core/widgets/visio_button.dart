import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';

/// VisioButton variants.
enum VisioButtonVariant { primary, secondary, destructive }

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

  /// Visual variant: primary (filled), secondary (outlined), or destructive
  /// (text button with the error color, for irreversible actions).
  final VisioButtonVariant variant;

  /// If true, expands to fill all available width.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild(context);

    final onPressedOrNull = isLoading ? null : onPressed;
    final button = switch (variant) {
      VisioButtonVariant.primary =>
        ElevatedButton(onPressed: onPressedOrNull, child: child),
      VisioButtonVariant.secondary =>
        OutlinedButton(onPressed: onPressedOrNull, child: child),
      VisioButtonVariant.destructive => TextButton(
          onPressed: onPressedOrNull,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: child,
        ),
    };

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
      // The box keeps the button at the spinner's size: the indicator's own
      // Center would otherwise fill the button's width (SPEC 0123).
      return SizedBox(
        height: 20,
        width: 20,
        child: LoadingIndicator(
          size: 20,
          strokeWidth: 2,
          color: switch (variant) {
            VisioButtonVariant.primary =>
              Theme.of(context).colorScheme.onPrimary,
            VisioButtonVariant.secondary =>
              Theme.of(context).colorScheme.primary,
            VisioButtonVariant.destructive =>
              Theme.of(context).colorScheme.error,
          },
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          // Wraps at large text instead of running past the button (SPEC 0121).
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      );
    }

    return Text(label);
  }
}
