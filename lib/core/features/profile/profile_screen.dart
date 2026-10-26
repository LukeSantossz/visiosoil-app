import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/core/widgets/google_sign_in_button.dart';
import 'package:visiosoil_app/core/widgets/account_card.dart';
import 'package:visiosoil_app/core/widgets/settings_tile.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Local records remain available independently of account state.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final account = auth.hasError
        ? ref.read(authServiceProvider).currentAccount
        : auth.value?.account;
    final records = ref.watch(soilRecordsStreamProvider);
    final list = records.value;
    final held = list
        ?.where((record) => record.hasClassification)
        .map((record) => record.textureClass!)
        .toSet();
    final classes = held?.length;
    // The collection counts the twelve USDA reference classes, as Home and
    // the history count them (SPEC 0203, SPEC 0204).
    final collected = held
        ?.intersection(SoilTextureColors.referenceClasses.keys.toSet())
        .length;
    final offline =
        ref.watch(connectivityStatusProvider).value ==
        ConnectivityStatus.offline;
    ref.listen(authNotifierProvider, (previous, next) {
      if (next.hasError && (previous?.isLoading ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível vincular. Tente de novo ou continue sem conta.',
            ),
          ),
        );
      }
    });
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            // Cards at 16 dp, the title 20 dp in and 12 dp below the safe
            // area (PNG 21, SPEC 0204).
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Perfil',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AccountCard(
                  name: account?.displayName,
                  email: account?.email,
                  // The sync action's 48 dp target ends 12 dp above the
                  // card's edge, its text 20 dp, as PNG 22 draws it.
                  bottomPadding: account == null
                      ? AppSpacing.lg + AppSpacing.xs
                      : AppSpacing.md,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (account == null) ...[
                        Text(
                          'Vincule uma conta para salvar e sincronizar suas análises. Se trocar ou perder o aparelho, elas não se perdem.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.palette.onSurfaceVariant,
                          ),
                        ),
                        if (list != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Icon(
                                LucideIcons.smartphone,
                                size: 20,
                                color: context.palette.primaryText,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '${list.length} análises e $classes classes guardadas neste aparelho',
                                  style: SettingsRowFrame.subtitleStyle(
                                    context,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        GoogleSignInButton(
                          isLoading: auth.isLoading,
                          onPressed: offline
                              ? null
                              : () => ref
                                    .read(authNotifierProvider.notifier)
                                    .signIn(),
                        ),
                        if (offline)
                          const Text(
                            'Sem conexão. Você pode vincular depois em Perfil.',
                          ),
                      ] else ...[
                        // PNG 22: a rule 16 dp under the header, then the
                        // sync row. The sync foundation has no remote backend
                        // yet (ADR 0022), so the row says where the data is,
                        // and its action says why it cannot sync.
                        const SizedBox(height: 2),
                        Divider(
                          key: const Key('account-sync-rule'),
                          height: context.palette.edgeWidth,
                          thickness: context.palette.edgeWidth,
                          color: context.palette.divider,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.cloud,
                              size: 20,
                              color: context.palette.primaryText,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Dados só neste aparelho',
                                style:
                                    AppTypography.resized(
                                      theme.textTheme.bodyMedium!,
                                      14,
                                      height: 20 / 14,
                                    ).copyWith(
                                      color: context.palette.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                ),
                              ),
                              onPressed: () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        AppStrings.syncNotAvailable,
                                      ),
                                    ),
                                  ),
                              child: Text(
                                'Sincronizar',
                                style: AppTypography.weighted(
                                  AppTypography.resized(
                                    theme.textTheme.labelLarge!,
                                    14,
                                    height: 20 / 14,
                                  ),
                                  600,
                                ).copyWith(color: context.palette.primaryText),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Placed and set as Home's section titles (SPEC 0203).
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Neste aparelho',
                      style: AppTypography.resized(
                        theme.textTheme.titleMedium!,
                        17,
                        height: 24 / 17,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (records.hasError) ...[
                  const Text('Não foi possível carregar suas análises.'),
                  TextButton(
                    onPressed: () => ref.invalidate(soilRecordsStreamProvider),
                    child: const Text('Tentar de novo'),
                  ),
                ] else if (records.isLoading)
                  const StatsRow(
                    cells: [
                      StatCell.skeleton(),
                      StatCell.skeleton(),
                      StatCell.skeleton(),
                    ],
                  )
                else
                  StatsRow(
                    cells: [
                      StatCell(
                        value: '${list!.length}',
                        label: 'análises',
                        icon: LucideIcons.scan,
                      ),
                      StatCell(
                        value: '$collected/12',
                        label: 'coleção',
                        icon: LucideIcons.layers,
                        semanticLabel: '$collected de 12 classes na coleção',
                      ),
                      StatCell(
                        value:
                            '${account == null ? list.length : list.where((record) => record.syncStatus == 'synced').length}',
                        label: account == null ? 'só no aparelho' : 'enviadas',
                        icon: account == null
                            ? LucideIcons.hardDriveDownload
                            : LucideIcons.cloudCheck,
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xl),
                SettingsGroup(
                  children: [
                    SettingsTile(
                      icon: LucideIcons.settings,
                      title: 'Configurações',
                      subtitle: 'Tema, câmera, dados e acessibilidade',
                      onTap: () => context.push('/settings'),
                    ),
                    SettingsTile(
                      icon: LucideIcons.circleHelp,
                      title: 'Como fotografar a amostra',
                      subtitle: 'Luz, distância e preparo',
                      onTap: () => context.push('/capture-guide'),
                    ),
                    if (account != null)
                      SettingsTile(
                        icon: LucideIcons.logOut,
                        title: 'Sair da conta',
                        subtitle: 'As análises continuam neste aparelho',
                        destructive: true,
                        trailing: const SizedBox.shrink(),
                        onTap: auth.isLoading
                            ? null
                            : () async {
                                final confirmed = await confirmDestructiveAction(
                                  context,
                                  title: 'Sair da conta?',
                                  message:
                                      'As análises continuam neste aparelho.',
                                  confirmLabel: 'Sair da conta',
                                );
                                if (confirmed && context.mounted) {
                                  await ref
                                      .read(authNotifierProvider.notifier)
                                      .signOut();
                                }
                              },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
