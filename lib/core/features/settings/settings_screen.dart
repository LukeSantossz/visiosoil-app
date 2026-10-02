import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
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
        title: const Text('Configurações'),
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

          // --- Appearance ---
          _SectionHeader(title: 'APARÊNCIA'),
          const SizedBox(height: AppSpacing.sm),
          const _ThemeModeSelector(),

          const SizedBox(height: AppSpacing.xl),

          // --- About ---
          _SectionHeader(title: 'SOBRE'),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.info_outline,
            title: 'Versão do app',
            trailing: pkgAsync.when(
              data: (pkg) => Text(
                '${pkg.version}+${pkg.buildNumber}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: context.palette.onSurfaceVariant,
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
                  color: context.palette.onSurfaceVariant,
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
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: context.palette.onSurfaceVariant,
            ),
            onTap: () => context.push('/onboarding'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _ErrorReportTile(),

          const SizedBox(height: AppSpacing.xl),

          // --- Danger zone ---
          _SectionHeader(title: 'DADOS'),
          const SizedBox(height: AppSpacing.sm),
          _SettingsTile(
            icon: Icons.delete_forever_outlined,
            title: 'Apagar todos os dados',
            iconColor: context.palette.error,
            titleColor: context.palette.error,
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
          'Tem certeza? Todos os registros de solo serão removidos permanentemente. '
          'Esta ação não pode ser desfeita.',
      confirmLabel: 'Apagar tudo',
    );

    if (confirmed && context.mounted) {
      // Read before the first await: ref is unusable once the screen is gone.
      final records = ref.read(soilRecordRepositoryProvider);
      final errorReport = ref.read(errorReportStoreProvider);
      await records.deleteAll();
      // The report is data the app keeps, so it goes too (SPEC 0110).
      await errorReport.clear();
      if (context.mounted) {
        ref.invalidate(errorReportHasEntriesProvider);
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

/// Shown when the account left the device but Google did not confirm revoking
/// the grant (SPEC 0113): retrying is no longer possible from the app.
const String _revokeFailureMessage =
    'A conta saiu deste aparelho, mas o Google não confirmou a revogação. '
    'Revogue o acesso em myaccount.google.com/connections.';

/// Shown instead of starting a sign-in the device cannot complete offline
/// (SPEC 0114). Kept in step with the literal in the widget test.
const String _signInNeedsConnectionMessage =
    'Sem conexão. Entrar com Google precisa de internet.';

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
          SnackBar(
            content: Text(
              next.error is AccountNotRevokedException
                  ? _revokeFailureMessage
                  : _authFailureMessage,
            ),
          ),
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
          _accountTile(context, ref, ref.read(authServiceProvider).currentAccount),
      data: (state) => _accountTile(context, ref, state.account),
    );
  }

  Widget _accountTile(
    BuildContext context,
    WidgetRef ref,
    AuthAccount? account,
  ) {
    if (account == null) return _signInTile(context, ref);
    return Column(
      children: [
        _SettingsTile(
          icon: Icons.account_circle_outlined,
          title: account.displayName ?? account.email,
          trailing: TextButton(
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
            child: const Text('Sair'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsTile(
          icon: Icons.person_remove_outlined,
          title: 'Excluir conta',
          iconColor: context.palette.error,
          titleColor: context.palette.error,
          onTap: () => _confirmDeleteAccount(context, ref),
        ),
      ],
    );
  }

  /// Deletes the account behind the shared confirmation (SPEC 0113). The
  /// records stay, and the confirmation says where they are erased.
  Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Excluir conta',
      message: 'Sua conta Google será desconectada do VisioSoil e o acesso '
          'concedido ao app será revogado. Seus registros de solo continuam '
          'neste aparelho; para apagá-los, use "Apagar todos os dados".',
      confirmLabel: 'Excluir conta',
    );
    if (!confirmed || !context.mounted) return;

    // Read before the await: ref is unusable once the screen is gone.
    final auth = ref.read(authNotifierProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    // A failure is reported by the listener in build.
    if (await auth.deleteAccount()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Conta excluída do VisioSoil.')),
      );
    }
  }

  Widget _signInTile(BuildContext context, WidgetRef ref) => _SettingsTile(
        icon: Icons.login,
        title: 'Entrar com Google',
        onTap: () => _signIn(context, ref),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: context.palette.onSurfaceVariant,
        ),
      );

  /// Starts a sign-in unless the device is known to be offline, where it could
  /// only fail. An unreadable status is not evidence of being offline, so it
  /// still tries.
  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    ConnectivityStatus? status;
    try {
      status = await ref.read(connectivityServiceProvider).current();
    } on Exception catch (e) {
      developer.log('connectivity read failed: $e', name: 'SettingsScreen');
    }
    if (!context.mounted) return;
    if (status == ConnectivityStatus.offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_signInNeedsConnectionMessage)),
      );
      return;
    }
    await ref.read(authNotifierProvider.notifier).signIn();
  }
}

// --- Theme Mode ---

/// The theme choice: follow the system, or keep the app light or dark. It
/// applies at once and persists (SPEC 0107).
class _ThemeModeSelector extends ConsumerWidget {
  const _ThemeModeSelector();

  static const _labels = {
    ThemeMode.system: 'Sistema',
    ThemeMode.light: 'Claro',
    ThemeMode.dark: 'Escuro',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: [
          for (final MapEntry(key: mode, value: label) in _labels.entries)
            ButtonSegment(value: mode, label: Text(label)),
        ],
        selected: {ref.watch(themeModeProvider)},
        onSelectionChanged: (selection) =>
            ref.read(themeModeProvider.notifier).select(selection.single),
      ),
    );
  }
}

// --- Error Report ---

/// Shares the local report of uncaught errors (SPEC 0110). Enabled only when
/// the report holds an entry; nothing leaves the phone unless the user shares.
class _ErrorReportTile extends ConsumerWidget {
  const _ErrorReportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasEntries = ref.watch(errorReportHasEntriesProvider).value ?? false;
    return _SettingsTile(
      icon: Icons.bug_report_outlined,
      title: AppStrings.errorReportTitle,
      subtitle: AppStrings.errorReportPrivacy,
      trailing: hasEntries
          ? Icon(
              Icons.share_outlined,
              size: 20,
              color: context.palette.onSurfaceVariant,
            )
          : Text(
              AppStrings.errorReportNothingToSend,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.palette.onSurfaceVariant,
                  ),
            ),
      onTap: hasEntries ? () => _share(context, ref) : null,
    );
  }

  /// Hands the report to the share sheet as a text file. It names the build
  /// and the OS version, and no device identifier or account. A failure is
  /// said on screen without its cause.
  Future<void> _share(BuildContext context, WidgetRef ref) async {
    // Read before the first await: ref is unusable once the screen is gone.
    final errorReport = ref.read(errorReportStoreProvider);
    final share = ref.read(shareServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pkg = await ref.read(packageInfoProvider.future);
      final text = await errorReport.render(
        appVersion: '${pkg.version}+${pkg.buildNumber}',
        osVersion:
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );
      await share.shareErrorReport(text);
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.errorReportShareFailed)),
      );
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
            color: context.palette.onSurfaceVariant,
          ),
    );
  }
}

// --- Settings Tile ---

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: context.palette.surface,
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
              color: context.palette.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor ?? context.palette.onSurfaceVariant),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: titleColor,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.palette.onSurfaceVariant,
                        ),
                      ),
                  ],
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
