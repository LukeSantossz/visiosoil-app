import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Widget reutilizavel para exibir estado de permissao negada.
///
/// Mostra icone, titulo, descricao e botao para abrir configuracoes
/// quando a permissao foi negada permanentemente.
class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.isPermanentlyDenied = false,
    this.onRetry,
  });

  /// Icone representando a permissao (ex: Icons.camera_alt).
  final IconData icon;

  /// Titulo do estado de permissao negada.
  final String title;

  /// Descricao explicando por que a permissao e necessaria.
  final String description;

  /// Se true, mostra botao para abrir configuracoes do sistema.
  /// Se false, mostra botao para tentar novamente.
  final bool isPermanentlyDenied;

  /// Callback quando o usuario toca em "Tentar novamente".
  /// Ignorado se [isPermanentlyDenied] for true.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (isPermanentlyDenied)
              FilledButton.icon(
                onPressed: () => PermissionService.openSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Abrir Configuracoes'),
              )
            else if (onRetry != null)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
          ],
        ),
      ),
    );
  }
}
