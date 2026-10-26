import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_panel.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
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
    final pages = [
      _AccountStep(onNext: _next),
      _StepPage(
        step: 1,
        art: OnboardingArt.photograph,
        title: 'Fotografe a amostra de solo',
        description:
            'Destorroe uma porção da camada de 0–20 cm e enquadre na moldura. '
            'O app checa luz, foco e distância antes de liberar a foto.',
        // PNG 05 draws no list: the A4-sheet protocol is taught by the
        // capture guide, shown before the first camera launch (SPEC 0142,
        // SPEC 0206).
        actions: [
          _primary('Continuar', _next),
          _textAction('Pular', _complete),
        ],
      ),
      _StepPage(
        step: 2,
        art: OnboardingArt.triangle,
        title: 'Veja a classe textural estimada',
        description:
            'O resultado mostra a classe textural estimada pelo modelo e a '
            'confiança dela, em palavras e em percentual.',
        actions: [
          _primary('Continuar', _next),
          _textAction('Pular', _complete),
        ],
      ),
      _StepPage(
        step: 3,
        art: OnboardingArt.camera,
        title: 'Permita o acesso à câmera',
        description:
            'Usamos a câmera para fotografar o solo. Funciona sem internet; as '
            'análises sincronizam quando houver sinal.',
        extra: const Column(
          children: [
            _ListRow(
              icon: LucideIcons.camera,
              description:
                  'Câmera, para fotografar a amostra. As fotos ficam no '
                  'aparelho.',
            ),
            _ListRow(
              icon: LucideIcons.mapPin,
              description:
                  'Localização aproximada, opcional, para registrar onde a '
                  'amostra foi coletada.',
            ),
          ],
        ),
        actions: [
          _primary('Permitir câmera', _allowCamera),
          _textAction('Agora não', _complete),
        ],
      ),
    ];

    // The panel runs behind the status bar, so the page draws edge to edge
    // (PNG 02 to 07, SPEC 0206).
    return Scaffold(
      backgroundColor: context.palette.background,
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _currentPage = i),
        children: pages,
      ),
    );
  }
}

/// A step's 48 dp primary action (SPEC 0206).
Widget _primary(String label, VoidCallback onPressed) => VisioButton(
  label: label,
  onPressed: onPressed,
  expanded: true,
  style: ElevatedButton.styleFrom(
    minimumSize: const Size(64, 48),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
);

/// A step's second action, as text under the first.
Widget _textAction(String label, VoidCallback onPressed) => VisioButton(
  label: label,
  onPressed: onPressed,
  variant: VisioButtonVariant.text,
  expanded: true,
  style: TextButton.styleFrom(
    minimumSize: const Size(64, 48),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
);

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
        step: 0,
        art: OnboardingArt.linked,
        title: 'Conta vinculada',
        description:
            'Suas análises vão sincronizar sozinhas quando houver internet.',
        actions: [
          // 16 dp above "Continuar", as PNG 04 draws it.
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _LinkedAccountRow(
              name: account.displayName,
              email: account.email,
            ),
          ),
          _primary('Continuar', onNext),
        ],
      );
    }
    return _StepPage(
      step: 0,
      art: OnboardingArt.account,
      title: 'Vincular conta para salvar e sincronizar suas análises',
      description:
          'Guardamos suas análises, fotos e coleção na sua conta Google. Sem '
          'conta, tudo fica só neste aparelho.',
      extra: offline
          ? Text(
              'Sem conexão. Você pode vincular depois em Perfil.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            )
          : null,
      actions: [
        GoogleSignInButton(
          isLoading: auth.isLoading,
          onPressed: offline
              ? null
              : () => ref.read(authNotifierProvider.notifier).signIn(),
        ),
        VisioButton(
          label: 'Agora não',
          onPressed: onNext,
          variant: VisioButtonVariant.secondary,
          // Set as the Google button's label above it (PNG 02).
          labelStyle: AppTypography.resized(
            Theme.of(context).textTheme.bodyLarge!,
            17,
            height: 24 / 17,
          ).copyWith(fontWeight: FontWeight.w500),
          expanded: true,
          // Dark ink on an outline rule (PNG 02).
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            foregroundColor: context.palette.onSurface,
            side: BorderSide(
              color: context.palette.outline,
              width: context.palette.edgeWidth,
            ),
          ),
        ),
      ],
    );
  }
}

/// The linked account above "Continuar" (PNG 04, SPEC 0206).
class _LinkedAccountRow extends StatelessWidget {
  const _LinkedAccountRow({this.name, this.email});

  final String? name;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final title = name ?? email ?? '';
    final initials = title
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    return Container(
      key: const Key('linked-account-row'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(
          color: palette.highContrast
              ? palette.cardBorder
              : palette.outlineVariant,
          width: palette.edgeWidth,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              initials,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.primaryText,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (email != null && email != title)
                  Text(
                    email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(LucideIcons.cloudCheck, size: 20, color: palette.onSurface),
        ],
      ),
    );
  }
}

/// One row of a step's list: a 20 dp icon and a sentence at 14/20
/// (SPEC 0206).
class _ListRow extends StatelessWidget {
  const _ListRow({required this.icon, required this.description});

  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.palette.primaryText),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A step as PNG 02 to 07 lay it out (SPEC 0206): the panel, the step bars
/// and count, the left-aligned headline and body, then the actions pinned to
/// the bottom. The content above the actions scrolls, as at large text
/// (SPEC 0121).
class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.step,
    required this.art,
    required this.title,
    required this.description,
    this.extra,
    required this.actions,
  });

  /// Zero-based.
  final int step;
  final OnboardingArt art;
  final String title;
  final String description;
  final Widget? extra;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnboardingPanel(art: art),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < _stepCount; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: Container(
                                key: const Key('onboardingStepBar'),
                                height: 4,
                                decoration: BoxDecoration(
                                  color: i <= step
                                      ? palette.primary
                                      : palette.surfaceContainerHigh,
                                  borderRadius: AppRadius.borderRadiusPill,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Passo ${step + 1} de $_stepCount',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: palette.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                      if (extra != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        extra!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // The content scrolls to 8 dp above the actions, so step 4's list
        // ends where PNG 07 ends it.
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl + bottom,
          ),
          child: Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                actions[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
