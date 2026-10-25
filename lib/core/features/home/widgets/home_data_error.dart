import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

/// Inline recovery for the local records stream; capture remains available.
class HomeDataError extends StatelessWidget {
  const HomeDataError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      children: [
        const Icon(Icons.error_outline),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Não foi possível carregar suas análises.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        VisioButton(
          label: 'Tentar de novo',
          onPressed: onRetry,
          variant: VisioButtonVariant.secondary,
        ),
      ],
    ),
  );
}
