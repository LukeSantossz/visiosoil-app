import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/widgets/google_g_logo.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// The Google brand button (redesign v11 §9), shared by Perfil and the
/// onboarding so the branding has one owner: the multicolour "G", the exact
/// label "Continuar com o Google" in Medium 14, and no app colour.
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
  Widget build(BuildContext context) => VisioButton(
    label: 'Continuar com o Google',
    leading: const GoogleGLogo(),
    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    variant: VisioButtonVariant.secondary,
    expanded: true,
    isLoading: isLoading,
    loadingLabel: 'Vinculando sua conta…',
    onPressed: onPressed,
  );
}
