import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Reusable widget for displaying a permission denied state.
///
/// Shows icon, title, description, and a button to open settings
/// when the permission was permanently denied.
class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.isPermanentlyDenied = false,
    this.onRetry,
  });

  /// Icon representing the permission (e.g. Icons.camera_alt).
  final IconData icon;

  /// Title of the permission denied state.
  final String title;

  /// Description explaining why the permission is needed.
  final String description;

  /// If true, shows a button to open the system settings.
  /// If false, shows a button to try again.
  final bool isPermanentlyDenied;

  /// Callback for when the user taps "Tentar novamente".
  /// Ignored if [isPermanentlyDenied] is true.
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
