import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Provider for app information (version, build).
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
          // --- Account ---
          _SectionHeader(title: 'CONTA'),
          const SizedBox(height: AppSpacing.sm),
          const _AccountTile(),

          const SizedBox(height: AppSpacing.xl),

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
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Apagar todos os dados',
      message:
          'Tem certeza? Todos os registros de solo serao removidos permanentemente. '
          'Esta acao nao pode ser desfeita.',
      confirmLabel: 'Apagar tudo',
    );

    if (confirmed && context.mounted) {
      await ref.read(soilRecordRepositoryProvider).deleteAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todos os dados foram apagados.')),
        );
      }
    }
  }
}

// --- Account Tile ---

/// Shown when an interactive sign-in or sign-out fails, so the failure is never
/// silently swallowed. Kept in step with the literal in the widget test.
const String _authFailureMessage =
    'Não foi possível concluir a operação. Tente novamente.';

/// Sign-in / sign-out entry reflecting [authNotifierProvider]. Signing in or
/// out is the only place the app touches authentication; everything else works
/// unauthenticated.
class _AccountTile extends ConsumerWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface auth failures the user would otherwise never see: signIn/signOut
    // route errors into an AsyncError state, reported here as a one-off
    // SnackBar. Guarded on a loading -> error transition so an unrelated
    // rebuild cannot re-toast a stale error.
    ref.listen(authNotifierProvider, (previous, next) {
      if (next.hasError && (previous?.isLoading ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_authFailureMessage)),
        );
      }
    });

    final authAsync = ref.watch(authNotifierProvider);

    return authAsync.when(
      loading: () => const _SettingsTile(
        icon: Icons.account_circle_outlined,
        title: 'Conta',
        trailing: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // On error, derive the tile from the service's authoritative sign-in
      // snapshot rather than assuming signed-out: a sign-out that fails to clear
      // local credentials leaves the account present, so it must keep showing
      // the account instead of the sign-in affordance.
      error: (_, _) =>
          _accountTile(ref, ref.read(authServiceProvider).currentAccount),
      data: (state) => _accountTile(ref, state.account),
    );
  }

  Widget _accountTile(WidgetRef ref, AuthAccount? account) {
    if (account == null) return _signInTile(ref);
    return _SettingsTile(
      icon: Icons.account_circle_outlined,
      title: account.displayName ?? account.email,
      trailing: TextButton(
        onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
        child: const Text('Sair'),
      ),
    );
  }

  Widget _signInTile(WidgetRef ref) => _SettingsTile(
        icon: Icons.login,
        title: 'Entrar com Google',
        onTap: () => ref.read(authNotifierProvider.notifier).signIn(),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppColors.onSurfaceVariant,
        ),
      );
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
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
