import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/capture_protocol.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

/// Data for each onboarding step.
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

  /// The step's accent, taken from the theme it is drawn under (SPEC 0107).
  final Color Function(AppPalette) color;
}

// Each step's accent, in the protocol's order.
final _stepColors = <Color Function(AppPalette)>[
  (p) => p.primary,
  (p) => p.warning,
  (p) => p.secondary,
];

// The capture protocol the A4-sheet reader assumes, from the list the capture
// guide reads too (SPEC 0104, SPEC 0142).
final _steps = [
  for (final (i, step) in captureProtocolSteps.indexed)
    _OnboardingStep(
      icon: step.icon,
      title: step.title,
      description: step.description,
      color: _stepColors[i],
    ),
];

/// Capture onboarding with 3 illustrated steps.
///
/// Uses [PageView] for navigation between steps. Finishing the last step or
/// skipping marks the onboarding as completed (so first-launch gating shows it
/// only once) and then leaves: it pops back when opened over another route, or
/// goes home when it replaced Splash on first launch. Settings opens the capture
/// guide instead since SPEC 0142, so first launch is its only entry today.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

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
    if (_currentPage < _steps.length - 1) {
      // A page slide is a scroll, which the framework does not shorten when
      // the platform asks for no animations, so it jumps instead (SPEC 0120).
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(_currentPage + 1);
      } else {
        _controller.nextPage(
          duration: AppMotion.slow,
          curve: AppMotion.standard,
        );
      }
    } else {
      _complete();
    }
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

    return Scaffold(
      backgroundColor: context.palette.background,
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
                  Expanded(
                    child: Text(
                      'Como capturar',
                      style: theme.textTheme.titleMedium,
                    ),
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

    // Scrolls when a step is taller than the page, as at large text, and
    // stays centred when it fits (SPEC 0121).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Illustration placeholder
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: context.palette.discFill(
                    step.color(context.palette),
                    alpha: 0.12,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  step.icon,
                  size: 72,
                  color: context.palette.discInk(step.color(context.palette)),
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
                  color: context.palette.onSurfaceVariant,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
