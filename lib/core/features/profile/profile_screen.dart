import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/core/widgets/google_g_logo.dart';
import 'package:visiosoil_app/core/widgets/account_card.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
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
    final classes = list
        ?.where((record) => record.hasClassification)
        .map((record) => record.textureClass)
        .toSet()
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg + AppSpacing.xs),
              children: [
                Text(
                  'Perfil',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                AccountCard(
                  name: account?.displayName,
                  email: account?.email,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (account == null) ...[
                        const Text(
                          'Vincule uma conta para salvar e sincronizar suas análises. Se trocar ou perder o aparelho, elas não se perdem.',
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (list != null)
                          Text(
                            '${list.length} análises e $classes classes guardadas neste aparelho',
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        VisioButton(
                          label: 'Continuar com o Google',
                          leading: const GoogleGLogo(),
                          labelStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          variant: VisioButtonVariant.secondary,
                          expanded: true,
                          isLoading: auth.isLoading,
                          loadingLabel: 'Vinculando sua conta…',
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
                        const Text('Dados só neste aparelho'),
                        // The sync foundation has no remote backend yet (ADR 0022).
                        const TextButton(
                          onPressed: null,
                          child: Text('Sincronizar'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Neste aparelho',
                  style: Theme.of(context).textTheme.titleMedium,
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
                        icon: Icons.crop_free,
                      ),
                      StatCell(
                        value: '$classes/12',
                        label: 'coleção',
                        icon: Icons.layers_outlined,
                      ),
                      StatCell(
                        value:
                            '${account == null ? list.length : list.where((record) => record.syncStatus == 'synced').length}',
                        label: account == null ? 'só no aparelho' : 'enviadas',
                        icon: Icons.cloud_done_outlined,
                      ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xl),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('Configurações'),
                        subtitle: const Text(
                          'Tema, câmera, dados e acessibilidade',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.help_outline),
                        title: const Text('Como fotografar a amostra'),
                        subtitle: const Text('Luz, distância e preparo'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/capture-guide'),
                      ),
                      if (account != null) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            Icons.logout,
                            color: context.palette.error,
                          ),
                          title: Text(
                            'Sair da conta',
                            style: TextStyle(color: context.palette.error),
                          ),
                          subtitle: const Text(
                            'As análises continuam neste aparelho',
                          ),
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
