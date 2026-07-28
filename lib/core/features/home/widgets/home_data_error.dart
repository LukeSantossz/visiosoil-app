import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';

/// Inline error+retry shown on the home dashboard when the records stream
/// fails. The hero and the primary capture action stay above it; only the
/// stats and last-analysis region is replaced by this card.
class HomeDataError extends StatelessWidget {
  const HomeDataError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: ErrorState(
        message: 'Não foi possível carregar seus dados.',
        onRetry: onRetry,
      ),
    );
  }
}
