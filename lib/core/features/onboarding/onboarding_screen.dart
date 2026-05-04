import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Dados de cada passo do onboarding.
class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

const _steps = [
  _OnboardingStep(
    icon: Icons.crop_free,
    title: 'Enquadramento',
    description:
        'Posicione a moeda ao lado da amostra como referência de escala. '
        'Centralize o solo no visor ocupando pelo menos 70% da tela.',
    color: AppColors.primary,
  ),
  _OnboardingStep(
    icon: Icons.wb_sunny_outlined,
    title: 'Iluminação',
    description:
        'Prefira luz natural difusa. Evite sombras sobre a amostra e '
        'não use flash — ele altera as cores reais do solo.',
    color: AppColors.warning,
  ),
  _OnboardingStep(
    icon: Icons.straighten,
    title: 'Ângulo',
    description:
        'Fotografe de cima para baixo (top-down), mantendo o celular '
        'paralelo à superfície da amostra a cerca de 20 cm.',
    color: AppColors.secondary,
  ),
];

/// Onboarding de captura com 3 passos ilustrados.
///
/// Usa [PageView] para navegação entre passos. O callback [onComplete]
/// é chamado ao pressionar "Começar" no último passo.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _steps.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  void _complete() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header with skip
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
                  Text(
                    'Como capturar',
                    style: theme.textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: _complete,
                    child: const Text('Pular'),
                  ),
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
                children: List.generate(_steps.length, (i) {
                  final active = i <= _currentPage;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i < _steps.length - 1 ? AppSpacing.xs : 0,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        borderRadius: AppRadius.borderRadiusPill,
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, i) => _StepPage(step: _steps[i]),
              ),
            ),
            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(
                    _currentPage == _steps.length - 1
                        ? 'Começar'
                        : 'Próximo',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  const _StepPage({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration placeholder
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: step.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              step.icon,
              size: 72,
              color: step.color,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            step.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            step.description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
