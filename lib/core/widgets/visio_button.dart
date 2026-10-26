import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/press_scale.dart';

/// VisioButton variants (redesign v11 §4: primary/outlined/text/destructive).
/// [secondary] is this repo's existing name for the outlined variant; [text]
/// is the plain, neutral-colored text button added for the redesign, distinct
/// from [destructive]'s error-colored one.
enum VisioButtonVariant { primary, secondary, text, destructive }

/// Standardized VisioSoil button.
class VisioButton extends StatelessWidget {
  const VisioButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.labelStyle,
    this.isLoading = false,
    this.loadingLabel,
    this.variant = VisioButtonVariant.primary,
    this.expanded = false,
    this.singleLine = false,
  }) : assert(leading == null || icon == null);

  /// Button text.
  final String label;

  /// Callback when pressed.
  final VoidCallback? onPressed;

  /// Optional icon to the left of the label.
  final IconData? icon;

  /// Custom leading artwork, with a 10dp gap before the label.
  final Widget? leading;

  /// Optional product-specific label typography.
  final TextStyle? labelStyle;

  /// If true, shows a loading indicator instead of the content.
  final bool isLoading;

  /// Text shown next to the spinner while [isLoading] (redesign v11 §4:
  /// "spinner + label alternativo"). Null keeps the spinner alone, matching
  /// this button's behavior before the redesign.
  final String? loadingLabel;

  /// Visual variant: primary (filled), secondary (outlined), text (plain,
  /// neutral-colored), or destructive (text button with the error color, for
  /// irreversible actions).
  final VisioButtonVariant variant;

  /// If true, expands to fill all available width.
  final bool expanded;

  /// Keeps the label on one line, scaled down where it does not fit, as the
  /// result's side-by-side footer needs (SPEC 0202).
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final child = _buildChild(context);

    final onPressedOrNull = isLoading ? null : onPressed;
    // Shrinks to 0.98 while pressed (SPEC 0134).
    final button = PressScale(
      scale: 0.98,
      builder: (states) => switch (variant) {
        VisioButtonVariant.primary => ElevatedButton(
          onPressed: onPressedOrNull,
          statesController: states,
          child: child,
        ),
        VisioButtonVariant.secondary => OutlinedButton(
          onPressed: onPressedOrNull,
          statesController: states,
          child: child,
        ),
        VisioButtonVariant.text => TextButton(
          onPressed: onPressedOrNull,
          statesController: states,
          child: child,
        ),
        VisioButtonVariant.destructive => TextButton(
          onPressed: onPressedOrNull,
          statesController: states,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: child,
        ),
      },
    );

    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }

  Widget _buildChild(BuildContext context) {
    if (isLoading) {
      final spinnerColor = switch (variant) {
        VisioButtonVariant.primary => Theme.of(context).colorScheme.onPrimary,
        VisioButtonVariant.secondary ||
        VisioButtonVariant.text => Theme.of(context).colorScheme.primary,
        VisioButtonVariant.destructive => Theme.of(context).colorScheme.error,
      };

      final loadingLabel = this.loadingLabel;
      if (loadingLabel != null) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: LoadingIndicator(
                size: 16,
                strokeWidth: 2,
                color: spinnerColor,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(loadingLabel, textAlign: TextAlign.center)),
          ],
        );
      }

      // The box keeps the button at the spinner's size: the indicator's own
      // Center would otherwise fill the button's width (SPEC 0123).
      return SizedBox(
        height: 20,
        width: 20,
        child: LoadingIndicator(size: 20, strokeWidth: 2, color: spinnerColor),
      );
    }

    if (leading != null || icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ?? Icon(icon, size: 20),
          SizedBox(width: leading != null ? 10 : 8),
          // Wraps at large text instead of running past the button (SPEC 0121).
          Flexible(child: _label()),
        ],
      );
    }

    return _label();
  }

  Widget _label() => singleLine
      ? FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: labelStyle),
        )
      : Text(label, textAlign: TextAlign.center, style: labelStyle);
}
