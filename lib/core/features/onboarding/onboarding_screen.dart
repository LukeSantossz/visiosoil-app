import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/capture_protocol.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/account_card.dart';
import 'package:visiosoil_app/core/widgets/google_sign_in_button.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

const _stepCount = 4;

/// The onboarding in four steps (redesign v11 §3.2, SPEC 0199): an optional
/// Google link, the photograph with the capture protocol, the estimated
/// class, and the camera permission.
///
/// Finishing the last step or skipping marks the onboarding as completed (so
/// first-launch gating shows it only once) and then leaves: it pops back when
/// opened over another route, or goes home when it replaced Splash on first
/// launch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.requestCameraPermission});

  /// Asks for the camera; defaults to [PermissionService.requestCamera].
  final Future<AppPermissionStatus> Function()? requestCameraPermission;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    // A page slide is a scroll, which the framework does not shorten when
    // the platform asks for no animations, so it jumps instead (SPEC 0120).
    // User's reduce motion preference also jumps (redesign v11 §6.5).
    if (AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(_currentPage + 1);
    } else {
      _controller.nextPage(duration: AppMotion.slow, curve: AppMotion.standard);
    }
  }

  // A denial is handled where it matters, by capture's denied view.
  Future<void> _allowCamera() async {
    await (widget.requestCameraPermission ?? PermissionService.requestCamera)();
    await _complete();
  }

  Future<void> _complete() async {
    await ref.read(onboardingStoreProvider).markOnboardingCompleted();
    if (!mounted) return;

    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = [
      _AccountStep(onNext: _next),
      _StepPage(
        illustration: _Disc(
          icon: Icons.photo_camera_outlined,
          color: (p) => p.warning,
        ),
        title: 'Fotografe a amostra de solo',
        description:
            'Destorroe uma porção da camada de 0–20 cm e enquadre na moldura. '
            'O app checa luz, foco e distância antes de liberar a foto.',
        // The protocol the A4-sheet reader assumes, from the list the capture
        // guide reads too (SPEC 0104, SPEC 0142).
        extra: Column(
          children: [
            for (final step in captureProtocolSteps)
              _ListRow(
                icon: step.icon,
                title: step.title,
                description: step.description,
              ),
          ],
        ),
        actions: [
          VisioButton(label: 'Continuar', onPressed: _next, expanded: true),
        ],
      ),
      _StepPage(
        illustration: const SizedBox(width: 200, child: TextureTriangle()),
        title: 'Veja a classe textural estimada',
        description:
            'O resultado mostra a classe textural estimada pelo modelo e a '
            'confiança dela, em palavras e em percentual.',
        actions: [
          VisioButton(label: 'Continuar', onPressed: _next, expanded: true),
        ],
      ),
      _StepPage(
        illustration: _Disc(
          icon: Icons.camera_outlined,
          color: (p) => p.secondary,
        ),
        title: 'Permita o acesso à câmera',
        description:
            'Usamos a câmera para fotografar o solo. Funciona sem internet; as '
            'análises sincronizam quando houver sinal.',
        extra: const Column(
          children: [
            _ListRow(
              icon: Icons.photo_camera_outlined,
              description:
                  'Câmera, para fotografar a amostra. As fotos ficam no '
                  'aparelho.',
            ),
            _ListRow(
              icon: Icons.location_on_outlined,
              description:
                  'Localização aproximada, opcional, para registrar onde a '
                  'amostra foi coletada.',
            ),
          ],
        ),
        actions: [
          VisioButton(
            label: 'Permitir câmera',
            onPressed: _allowCamera,
            expanded: true,
          ),
          VisioButton(
            label: 'Agora não',
            onPressed: _complete,
            variant: VisioButtonVariant.text,
            expanded: true,
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header with the step count and skip
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Passo ${_currentPage + 1} de $_stepCount',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(onPressed: _complete, child: const Text('Pular')),
                ],
              ),
            ),
            // Progress indicators
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: List.generate(_stepCount, (i) {
                  final active = i <= _currentPage;
                  return Expanded(
                    child: Container(
                      key: const Key('onboardingStepBar'),
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i < _stepCount - 1 ? AppSpacing.xs : 0,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? context.palette.primary
                            : context.palette.outlineVariant,
                        borderRadius: AppRadius.borderRadiusPill,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Page content
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: pages,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 1: link a Google account, or not (redesign v11 §3.2, §9).
class _AccountStep extends ConsumerWidget {
  const _AccountStep({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    final account = auth.hasError ? null : auth.value?.account;
    final offline =
        ref.watch(connectivityStatusProvider).value ==
        ConnectivityStatus.offline;
    ref.listen(authNotifierProvider, (previous, next) {
      if (!(previous?.isLoading ?? false)) return;
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível vincular. Tente de novo ou continue sem conta.',
            ),
          ),
        );
      } else if (next.value?.isSignedIn ?? false) {
        AppHaptics.linked();
      }
    });

    if (account != null) {
      return _StepPage(
        illustration: _Disc(
          icon: Icons.cloud_done_outlined,
          color: (p) => p.primary,
        ),
        title: 'Conta vinculada',
        description:
            'Suas análises vão sincronizar sozinhas quando houver internet.',
        extra: AccountCard(
          name: account.displayName,
          email: account.email,
          child: const SizedBox.shrink(),
        ),
        actions: [
          VisioButton(label: 'Continuar', onPressed: onNext, expanded: true),
        ],
      );
    }
    return _StepPage(
      illustration: _Disc(
        icon: Icons.cloud_sync_outlined,
        color: (p) => p.primary,
      ),
      title: 'Vincular conta para salvar e sincronizar suas análises',
      description:
          'Guardamos suas análises, fotos e coleção na sua conta Google. Sem '
          'conta, tudo fica só neste aparelho.',
      actions: [
        GoogleSignInButton(
          isLoading: auth.isLoading,
          onPressed: offline
              ? null
              : () => ref.read(authNotifierProvider.notifier).signIn(),
        ),
        if (offline)
          Text(
            'Sem conexão. Você pode vincular depois em Perfil.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.palette.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        VisioButton(
          label: 'Agora não',
          onPressed: onNext,
          variant: VisioButtonVariant.text,
          expanded: true,
        ),
      ],
    );
  }
}

/// A step's illustration disc, tinted from the theme it is drawn under
/// (SPEC 0107).
class _Disc extends StatelessWidget {
  const _Disc({required this.icon, required this.color});

  final IconData icon;
  final Color Function(AppPalette) color;

  @override
  Widget build(BuildContext context) {
    final accent = color(context.palette);
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: context.palette.discFill(accent, alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 72, color: context.palette.discInk(accent)),
    );
  }
}

/// One row of a step's list: an icon, an optional title, and a sentence.
class _ListRow extends StatelessWidget {
  const _ListRow({required this.icon, this.title, required this.description});

  final IconData icon;
  final String? title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.palette.primaryText),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!, style: theme.textTheme.titleSmall),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.illustration,
    required this.title,
    required this.description,
    this.extra,
    required this.actions,
  });

  final Widget illustration;
  final String title;
  final String description;
  final Widget? extra;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Scrolls when a step is taller than the page, as at large text, and
    // stays centred when it fits (SPEC 0121). The actions close the scroll so
    // they are never covered.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.lg),
              illustration,
              const SizedBox(height: AppSpacing.xxl),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: context.palette.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.xl),
                extra!,
              ],
              const SizedBox(height: AppSpacing.xl),
              for (final action in actions) ...[
                action,
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
