import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Provider para informacoes do app (versao, build).
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pkgAsync = ref.watch(packageInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuracoes'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // --- About ---
          _SectionHeader(title: 'SOBRE'),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'Versao do app',
            trailing: pkgAsync.when(
              data: (pkg) => Text(
                '${pkg.version}+${pkg.buildNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              loading: () => const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => Text(
                '-',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // --- Help ---
          _SectionHeader(title: 'AJUDA'),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.school_outlined,
            title: 'Como capturar bem',
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.onSurfaceVariant,
            ),
            onTap: () => context.push('/onboarding'),
          ),

          const SizedBox(height: AppSpacing.xl),

          // --- Danger zone ---
          _SectionHeader(title: 'DADOS'),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: 'Apagar todos os dados',
            iconColor: AppColors.error,
            titleColor: AppColors.error,
            onTap: () => _confirmDeleteAll(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar todos os dados'),
        content: const Text(
          'Tem certeza? Todos os registros de solo serao removidos permanentemente. '
          'Esta acao nao pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Apagar tudo'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final repo = ref.read(soilRecordRepositoryProvider);
      final all = await repo.getAll();
      final ids = all.where((r) => r.id != null).map((r) => r.id!).toList();
      if (ids.isNotEmpty) {
        await repo.deleteByIds(ids);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todos os dados foram apagados.')),
        );
      }
    }
  }
}

// --- Section Header ---

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: AppColors.onSurfaceVariant,
          ),
    );
  }
}

// --- Settings Tile ---

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.borderRadiusMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor ?? AppColors.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: titleColor,
                  ),
                ),
              ),
              if (trailing != null) ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
