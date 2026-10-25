import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visiosoil_app/core/constants/app_links.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/settings_switch_tile.dart';
import 'package:visiosoil_app/core/features/settings/export_sheet.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/text_size_provider.dart';
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
      appBar: const VisioAppBar(title: 'Configurações'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg + AppSpacing.xs),
            children: [
              const _SectionHeader(title: 'CONTA'),
              const SizedBox(height: AppSpacing.sm),
              const _AccountTile(),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'PREFERÊNCIAS'),
              const SizedBox(height: AppSpacing.sm),
              _SettingsGroup(
                children: [
                  const _ThemeChoiceSelector(),
                  SettingsSwitchTile(
                    icon: Icons.wb_sunny_outlined,
                    title: 'Modo Sol',
                    subtitle: 'Alto contraste e letras maiores para o campo',
                    value: ref.watch(sunModeProvider),
                    onChanged: (on) =>
                        ref.read(sunModeProvider.notifier).select(on),
                  ),
                  const _VibrationSwitch(),
                  const _SettingsTile(
                    icon: Icons.straighten,
                    title: 'Unidades',
                    subtitle: 'Distância em cm',
                  ),
                  const _SettingsTile(
                    icon: Icons.translate,
                    title: 'Idioma',
                    subtitle: 'Português (Brasil)',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'CÂMERA E ANÁLISE'),
              const SizedBox(height: AppSpacing.sm),
              const _SettingsGroup(
                children: [
                  SettingsSwitchTile(
                    icon: Icons.crop_free,
                    title: 'Guia de enquadramento',
                    subtitle: 'Moldura e checagem de luz, foco e distância',
                    value: true,
                    onChanged: null,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.image_outlined,
                    title: 'Salvar fotos na galeria',
                    value: false,
                    onChanged: null,
                  ),
                  SettingsSwitchTile(
                    icon: Icons.location_on_outlined,
                    title: 'Registrar localização',
                    subtitle: 'Aproximada, opcional',
                    value: false,
                    onChanged: null,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'DADOS E SINCRONIZAÇÃO'),
              const SizedBox(height: AppSpacing.sm),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.backup_outlined,
                    title: 'Backup na conta',
                    subtitle:
                        ref.watch(authNotifierProvider).value?.account == null
                        ? 'Requer conta vinculada'
                        : 'Dados só neste aparelho',
                  ),
                  const SettingsSwitchTile(
                    icon: Icons.wifi,
                    title: 'Sincronizar só no Wi-Fi',
                    value: true,
                    onChanged: null,
                  ),
                  _SettingsTile(
                    icon: Icons.file_download_outlined,
                    title: 'Exportar análises',
                    subtitle: 'Planilha CSV',
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => const ExportSheet(),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.delete_outline,
                    title: 'Limpar dados do aparelho',
                    subtitle: 'Apaga análises e fotos locais',
                    destructive: true,
                    onTap: () => _confirmDeleteAll(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'ACESSIBILIDADE'),
              const SizedBox(height: AppSpacing.sm),
              _SettingsGroup(
                children: [
                  const _ReduceMotionSwitch(),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tamanho do texto',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SegmentedControl<bool>(
                          semanticLabel: 'Tamanho do texto',
                          value: ref.watch(largeTextProvider),
                          options: const [
                            SegmentedControlOption(
                              value: false,
                              label: 'Padrão',
                            ),
                            SegmentedControlOption(
                              value: true,
                              label: 'Grande',
                            ),
                          ],
                          onChanged: (large) => ref
                              .read(largeTextProvider.notifier)
                              .select(large),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeader(title: 'SOBRE E AJUDA'),
              const SizedBox(height: AppSpacing.sm),
              _SettingsGroup(
                children: [
                  _SettingsTile(
                    icon: Icons.school_outlined,
                    title: 'Como fotografar a amostra',
                    onTap: () => context.push('/capture-guide'),
                  ),
                  const _PrivacyPolicyTile(),
                  const _ErrorReportTile(),
                  _SettingsTile(
                    icon: Icons.info_outline,
                    title: 'Versão',
                    trailing: pkgAsync.when(
                      data: (pkg) => Text(
                        '${pkg.version}+${pkg.buildNumber}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      loading: () => const SizedBox(
                        width: 16,
                        height: 16,
                        child: LoadingIndicator(size: 16, strokeWidth: 2),
                      ),
                      error: (_, _) => const Text('—'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
          child: LoadingIndicator(size: 16, strokeWidth: 2),
        ),
      ),
      // On error, derive the tile from the service's authoritative sign-in
      // snapshot rather than assuming signed-out: a sign-out that fails to clear
      // local credentials leaves the account present, so it must keep showing
      // the account instead of the sign-in affordance.
      error: (_, _) => _accountTile(
        context,
        ref,
        ref.read(authServiceProvider).currentAccount,
      ),
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
        // Destructive, like "Apagar todos os dados" (SPEC 0129).
        VisioButton(
          label: 'Excluir conta',
          icon: Icons.person_remove_outlined,
          variant: VisioButtonVariant.destructive,
          expanded: true,
          onPressed: () => _confirmDeleteAccount(context, ref),
        ),
      ],
    );
  }

  /// Deletes the account behind the shared confirmation (SPEC 0113). The
  /// records stay, and the confirmation says where they are erased.
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Excluir conta',
      message:
          'Sua conta Google será desconectada do VisioSoil e o acesso '
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
    title: 'Conta',
    subtitle: 'Não vinculada · dados só neste aparelho',
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

// --- Theme Choice ---

/// The base choice is retained while the independent Sun override is active.
class _ThemeChoiceSelector extends ConsumerWidget {
  const _ThemeChoiceSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tema', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        SegmentedControl<ThemeMode>(
          semanticLabel: 'Tema',
          value: ref.watch(baseThemeModeProvider),
          options: const [
            SegmentedControlOption(value: ThemeMode.system, label: 'Sistema'),
            SegmentedControlOption(value: ThemeMode.light, label: 'Claro'),
            SegmentedControlOption(value: ThemeMode.dark, label: 'Escuro'),
          ],
          onChanged: (choice) =>
              ref.read(baseThemeModeProvider.notifier).select(choice),
        ),
      ],
    ),
  );
}

/// Vibration toggle: subtle haptic feedback on capture, save, and complete
/// (redesign v11 §3.11). On by default.
class _VibrationSwitch extends ConsumerWidget {
  const _VibrationSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSwitchTile(
      title: 'Vibração',
      haptic: false,
      subtitle: 'Toques sutis ao capturar, salvar e concluir',
      value: ref.watch(vibrationProvider),
      onChanged: (on) {
        ref.read(vibrationProvider.notifier).select(on);
      },
    );
  }
}

/// Reduce motion toggle: swaps animations for short transitions
/// (redesign v11 §3.11, §6.5). Follows system by default.
class _ReduceMotionSwitch extends ConsumerWidget {
  const _ReduceMotionSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSwitchTile(
      title: 'Reduzir movimento',
      subtitle: 'Troca animações por transições curtas',
      value: ref.watch(reduceMotionProvider),
      onChanged: (on) {
        ref.read(reduceMotionProvider.notifier).select(on);
      },
    );
  }
}

// --- Privacy Policy ---

/// Shown when the policy could not be opened. Kept in step with the literal in
/// the widget test.
const String _privacyPolicyFailedMessage =
    'Não foi possível abrir a política de privacidade.';

/// Opens the published privacy policy in the browser, which shows its address
/// (SPEC 0157). A launch that fails is said on screen.
class _PrivacyPolicyTile extends StatelessWidget {
  const _PrivacyPolicyTile();

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.privacy_tip_outlined,
      title: 'Privacidade e dados',
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: context.palette.onSurfaceVariant,
      ),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    bool opened;
    try {
      opened = await launchUrl(
        Uri.parse(AppLinks.privacyPolicy),
        mode: LaunchMode.externalApplication,
      );
    } on PlatformException catch (e) {
      developer.log('privacy policy launch failed: $e', name: 'SettingsScreen');
      opened = false;
    } on MissingPluginException catch (e) {
      developer.log('privacy policy launch failed: $e', name: 'SettingsScreen');
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text(_privacyPolicyFailedMessage)),
      );
    }
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
      title: 'Enviar comentário',
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
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: context.palette.isSun ? 64 : 56,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: destructive
                    ? context.palette.error
                    : context.palette.primaryText,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: destructive ? context.palette.error : null,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.palette.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Flexible(child: trailing!)
              else if (onTap != null)
                Icon(
                  Icons.chevron_right,
                  color: context.palette.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index != 0)
            Divider(
              height: context.density.borderWidth,
              thickness: context.density.borderWidth,
              color: context.palette.divider,
            ),
          children[index],
        ],
      ],
    ),
  );
}
