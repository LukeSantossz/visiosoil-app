import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/widgets/google_g_logo.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// The Google brand button (redesign v11 §9), shared by Perfil and the
/// onboarding so the branding has one owner. It wears Google's colours, not
/// the app's, as PNG 21 draws it (SPEC 0204): a white fill with a #747775
/// rule and #1F1F1F text, or Google's dark variant, the 24 dp "G" 12 dp
/// before "Continuar com o Google" at 17 sp weight 500.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;

  /// Null disables the button, as offline does.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (fill, rule, ink) = palette.isSun
        ? (Colors.white, Colors.black, Colors.black)
        : palette.brightness == Brightness.dark
        ? (
            const Color(0xFF131314),
            const Color(0xFF8E918F),
            const Color(0xFFE3E3E3),
          )
        : (Colors.white, const Color(0xFF747775), const Color(0xFF1F1F1F));
    final label = AppTypography.resized(
      Theme.of(context).textTheme.bodyLarge!,
      17,
      height: 24 / 17,
    ).copyWith(fontWeight: FontWeight.w500, color: ink);
    return VisioButton(
      label: 'Continuar com o Google',
      leading: const GoogleGLogo(size: 24),
      leadingGap: 12,
      labelStyle: label,
      variant: VisioButtonVariant.secondary,
      expanded: true,
      isLoading: isLoading,
      loadingLabel: 'Vinculando sua conta…',
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        // The density's target: 48 dp, and Modo Sol's 56 (review of #438).
        minimumSize: Size(64, context.density.tap),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        backgroundColor: fill,
        foregroundColor: ink,
        side: BorderSide(color: rule, width: palette.isSun ? 2 : 1),
      ),
    );
  }
}
