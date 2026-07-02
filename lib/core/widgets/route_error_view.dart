import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Full-screen fallback the router shows when no route matches the requested
/// location (go_router also routes redirect and parse errors here). Renders a
/// localized message and a button that returns home.
class RouteErrorView extends StatelessWidget {
  const RouteErrorView({super.key, required this.onGoHome});

  /// Invoked when the user taps the "return home" button.
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Tela não encontrada',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'A página que você tentou abrir não existe.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onGoHome,
                icon: const Icon(Icons.home),
                label: const Text('Voltar ao início'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
