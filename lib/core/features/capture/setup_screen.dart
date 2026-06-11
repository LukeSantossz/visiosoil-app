import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/models/capture_context.dart';

/// Tela de setup pré-captura com wizard de 2 passos.
///
/// Permite selecionar cultura/época e profundidade antes de
/// abrir a câmera para captura da amostra de solo.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // Seleções do usuário
  Crop? _selectedCrop;
  PlantingSeason? _selectedSeason;
  SamplingDepth? _selectedDepth;

  static const _totalSteps = 2;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _openCamera();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.pop();
    }
  }

  void _openCamera() {
    final captureContext = CaptureContext(
      crop: _selectedCrop,
      plantingSeason: _selectedSeason,
      samplingDepth: _selectedDepth,
    );
    // Navega para a captura passando o contexto
    context.go('/capture', extra: captureContext);
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _selectedCrop != null && _selectedSeason != null;
      case 1:
        return _selectedDepth != null;
      default:
        return false;
    }
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Cultura e Época';
      case 1:
        return 'Profundidade';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_stepTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _previousStep,
        ),
      ),
      body: Column(
        children: [
          // Progress indicator
          _ProgressIndicator(
            currentStep: _currentStep,
            totalSteps: _totalSteps,
          ),
          // Page content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) => setState(() => _currentStep = index),
              children: [
                _CropSelectionStep(
                  selectedCrop: _selectedCrop,
                  selectedSeason: _selectedSeason,
                  onCropSelected: (crop) => setState(() => _selectedCrop = crop),
                  onSeasonSelected: (season) =>
                      setState(() => _selectedSeason = season),
                ),
                _DepthSelectionStep(
                  selectedDepth: _selectedDepth,
                  onDepthSelected: (depth) =>
                      setState(() => _selectedDepth = depth),
                  context: CaptureContext(
                    crop: _selectedCrop,
                    plantingSeason: _selectedSeason,
                    samplingDepth: _selectedDepth,
                  ),
                ),
              ],
            ),
          ),
          // Bottom buttons
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canProceed ? _nextStep : null,
                  child: Text(
                    _currentStep == _totalSteps - 1
                        ? 'Abrir Câmera'
                        : 'Próximo',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador de progresso do wizard.
class _ProgressIndicator extends StatelessWidget {
  const _ProgressIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: List.generate(totalSteps, (index) {
          final isActive = index <= currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                      borderRadius: AppRadius.borderRadiusPill,
                    ),
                  ),
                ),
                if (index < totalSteps - 1)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Passo 1: Seleção de cultura e época.
class _CropSelectionStep extends StatelessWidget {
  const _CropSelectionStep({
    required this.selectedCrop,
    required this.selectedSeason,
    required this.onCropSelected,
    required this.onSeasonSelected,
  });

  final Crop? selectedCrop;
  final PlantingSeason? selectedSeason;
  final ValueChanged<Crop> onCropSelected;
  final ValueChanged<PlantingSeason> onSeasonSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Seção de cultura
        Text(
          'Qual cultura está plantada?',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Grid de culturas 2x3
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.0,
          children: Crop.available
              .map((crop) => _CropCard(
                    crop: crop,
                    isSelected: selectedCrop?.id == crop.id,
                    onTap: () => onCropSelected(crop),
                  ))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.xxl),
        // Seção de época
        Text(
          'Época de plantio',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Chips de época
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: PlantingSeason.values.map((season) {
            final isSelected = selectedSeason == season;
            return ChoiceChip(
              label: Text(season.label),
              selected: isSelected,
              onSelected: (_) => onSeasonSelected(season),
              selectedColor: AppColors.primaryContainer,
              backgroundColor: AppColors.surface,
              side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Card de seleção de cultura.
class _CropCard extends StatelessWidget {
  const _CropCard({
    required this.crop,
    required this.isSelected,
    required this.onTap,
  });

  final Crop crop;
  final bool isSelected;
  final VoidCallback onTap;

  IconData _getCropIcon() {
    switch (crop.iconCodePoint) {
      case 'grass':
        return Icons.grass;
      case 'grain':
        return Icons.grain;
      case 'filter_vintage':
        return Icons.filter_vintage;
      case 'park':
        return Icons.park;
      case 'local_cafe':
        return Icons.local_cafe;
      case 'eco':
      default:
        return Icons.eco;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: AppRadius.borderRadiusMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getCropIcon(),
                size: 32,
                color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                crop.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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

/// Passo 2: Seleção de profundidade + resumo.
class _DepthSelectionStep extends StatelessWidget {
  const _DepthSelectionStep({
    required this.selectedDepth,
    required this.onDepthSelected,
    required this.context,
  });

  final SamplingDepth? selectedDepth;
  final ValueChanged<SamplingDepth> onDepthSelected;
  final CaptureContext context;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'Qual a profundidade da amostra?',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Cards de profundidade
        ...SamplingDepth.values.map((depth) => _DepthCard(
              depth: depth,
              isSelected: selectedDepth == depth,
              onTap: () => onDepthSelected(depth),
            )),
        const SizedBox(height: AppSpacing.xxl),
        // Resumo
        if (context.crop != null) ...[
          Text(
            'Resumo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceDim,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Column(
              children: [
                if (context.crop != null)
                  _SummaryRow(
                    icon: Icons.eco,
                    label: 'Cultura',
                    value: context.crop!.name,
                  ),
                if (context.plantingSeason != null)
                  _SummaryRow(
                    icon: Icons.calendar_today,
                    label: 'Época',
                    value: context.plantingSeason!.label,
                  ),
                if (selectedDepth != null)
                  _SummaryRow(
                    icon: Icons.straighten,
                    label: 'Profundidade',
                    value: selectedDepth!.label,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Card de seleção de profundidade.
class _DepthCard extends StatelessWidget {
  const _DepthCard({
    required this.depth,
    required this.isSelected,
    required this.onTap,
  });

  final SamplingDepth depth;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: isSelected ? AppColors.primaryContainer : AppColors.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Center(
                    child: Text(
                      '${depth.minCm}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isSelected
                            ? AppColors.onPrimary
                            : AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        depth.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        depth.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                  )
                else
                  const Icon(
                    Icons.circle_outlined,
                    color: AppColors.outlineVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de resumo.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$label:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
