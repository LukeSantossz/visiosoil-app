import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/capture_context.dart';

/// Tela de detalhes do lote com comparação temporal.
///
/// Exibe stats do lote, histórico de amostras e comparação A/B.
/// Dados mock por enquanto — persistência de lotes é feature futura.
class LotDetailScreen extends StatefulWidget {
  const LotDetailScreen({super.key, required this.lot});

  final Lot lot;

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {
  late List<_SampleData> _samples;
  int _selectedIndexA = 0;
  int _selectedIndexB = 1;

  @override
  void initState() {
    super.initState();
    _samples = _SampleData.mockForLot(widget.lot.id);
  }

  void _selectSample(int index) {
    setState(() {
      // Se já é A, não faz nada
      if (index == _selectedIndexA) return;
      // Se já é B, troca A e B
      if (index == _selectedIndexB) {
        final temp = _selectedIndexA;
        _selectedIndexA = _selectedIndexB;
        _selectedIndexB = temp;
        return;
      }
      // Senão, B vira A e o novo vira B
      _selectedIndexA = _selectedIndexB;
      _selectedIndexB = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sampleA = _samples.isNotEmpty ? _samples[_selectedIndexA] : null;
    final sampleB = _samples.length > 1 ? _samples[_selectedIndexB] : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.lot.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lot stats card
            _LotStatsCard(
              lot: widget.lot,
              sampleCount: _samples.length,
              crop: _samples.isNotEmpty ? _samples.first.crop : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Comparison section
            if (sampleA != null && sampleB != null) ...[
              Text(
                'Comparação Temporal',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _TemporalComparison(
                sampleA: sampleA,
                sampleB: sampleB,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],

            // Timeline section
            Text(
              'Histórico de Amostras',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _SampleTimeline(
              samples: _samples,
              selectedIndexA: _selectedIndexA,
              selectedIndexB: _selectedIndexB,
              onSampleTap: _selectSample,
            ),
            const SizedBox(height: AppSpacing.xl),

            // Action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (sampleA != null) {
                    context.push('/recommendations', extra: sampleA.textureClass);
                  }
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Ver plano de manejo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Lot Stats Card ---

class _LotStatsCard extends StatelessWidget {
  const _LotStatsCard({
    required this.lot,
    required this.sampleCount,
    this.crop,
  });

  final Lot lot;
  final int sampleCount;
  final Crop? crop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: const Icon(
                    Icons.landscape,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lot.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (lot.areHectares != null)
                        Text(
                          '${lot.areHectares} hectares',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            // Stats row
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    icon: Icons.grass,
                    label: 'Cultura',
                    value: crop != null ? '${crop!.icon} ${crop!.name}' : '-',
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    icon: Icons.science_outlined,
                    label: 'Amostras',
                    value: sampleCount.toString(),
                  ),
                ),
                Expanded(
                  child: _StatItem(
                    icon: Icons.calendar_today,
                    label: 'Última',
                    value: 'Hoje',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
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

    return Column(
      children: [
        Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// --- Temporal Comparison ---

class _TemporalComparison extends StatelessWidget {
  const _TemporalComparison({
    required this.sampleA,
    required this.sampleB,
  });

  final _SampleData sampleA;
  final _SampleData sampleB;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChanged = sampleA.textureClass != sampleB.textureClass;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: hasChanged
                    ? AppColors.warningContainer
                    : AppColors.primaryContainer,
                borderRadius: AppRadius.borderRadiusPill,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasChanged ? Icons.change_circle : Icons.check_circle,
                    size: 16,
                    color: hasChanged ? AppColors.warning : AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    hasChanged ? 'Mudou' : 'Estável',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasChanged ? AppColors.warning : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Comparison cards
            Row(
              children: [
                Expanded(
                  child: _ComparisonCard(
                    sample: sampleA,
                    label: 'A',
                    isOlder: sampleA.date.isBefore(sampleB.date),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Icon(
                    Icons.arrow_forward,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: _ComparisonCard(
                    sample: sampleB,
                    label: 'B',
                    isOlder: sampleB.date.isBefore(sampleA.date),
                  ),
                ),
              ],
            ),
            // Alert if changed
            if (hasChanged) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: AppRadius.borderRadiusMd,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'A textura do solo mudou entre as amostras. Revise o plano de manejo.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.sample,
    required this.label,
    required this.isOlder,
  });

  final _SampleData sample;
  final String label;
  final bool isOlder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textureColor = SoilTextureColors.forClass(sample.textureClass);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceDim,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          // Label badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: AppRadius.borderRadiusPill,
            ),
            child: Text(
              isOlder ? 'Anterior ($label)' : 'Recente ($label)',
              style: theme.textTheme.labelSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Texture dot and name
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: textureColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            sample.textureClass,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${sample.confidence.round()}%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _formatDate(sample.date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// --- Sample Timeline ---

class _SampleTimeline extends StatelessWidget {
  const _SampleTimeline({
    required this.samples,
    required this.selectedIndexA,
    required this.selectedIndexB,
    required this.onSampleTap,
  });

  final List<_SampleData> samples;
  final int selectedIndexA;
  final int selectedIndexB;
  final ValueChanged<int> onSampleTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(samples.length, (index) {
        final sample = samples[index];
        final isSelected = index == selectedIndexA || index == selectedIndexB;
        final selectionLabel = index == selectedIndexA
            ? 'A'
            : index == selectedIndexB
                ? 'B'
                : null;
        final isLast = index == samples.length - 1;

        return _TimelineItem(
          sample: sample,
          isSelected: isSelected,
          selectionLabel: selectionLabel,
          isLast: isLast,
          onTap: () => onSampleTap(index),
        );
      }),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.sample,
    required this.isSelected,
    required this.selectionLabel,
    required this.isLast,
    required this.onTap,
  });

  final _SampleData sample;
  final bool isSelected;
  final String? selectionLabel;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textureColor = SoilTextureColors.forClass(sample.textureClass);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusMd,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : textureColor,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                  child: isSelected
                      ? Center(
                          child: Text(
                            selectionLabel ?? '',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 56,
                    color: AppColors.outlineVariant,
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryContainer.withValues(alpha: 0.5)
                    : AppColors.surface,
                borderRadius: AppRadius.borderRadiusMd,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Texture color dot
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: textureColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sample.textureClass,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${sample.depth.label} · ${sample.confidence.round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Date
                  Text(
                    _formatDateShort(sample.date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime date) {
    final months = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

// --- Mock Data ---

class _SampleData {
  final String id;
  final DateTime date;
  final String textureClass;
  final double confidence;
  final SamplingDepth depth;
  final Crop crop;

  const _SampleData({
    required this.id,
    required this.date,
    required this.textureClass,
    required this.confidence,
    required this.depth,
    required this.crop,
  });

  static List<_SampleData> mockForLot(String lotId) {
    final now = DateTime.now();

    // Different mock data based on lot to show variety
    switch (lotId) {
      case '1': // Lote Norte - shows change
        return [
          _SampleData(
            id: '1',
            date: now,
            textureClass: 'Argilosa',
            confidence: 87.5,
            depth: SamplingDepth.shallow,
            crop: Crop.available[0], // Soja
          ),
          _SampleData(
            id: '2',
            date: now.subtract(const Duration(days: 90)),
            textureClass: 'Média',
            confidence: 82.3,
            depth: SamplingDepth.shallow,
            crop: Crop.available[0],
          ),
          _SampleData(
            id: '3',
            date: now.subtract(const Duration(days: 180)),
            textureClass: 'Média',
            confidence: 79.1,
            depth: SamplingDepth.medium,
            crop: Crop.available[1], // Milho
          ),
        ];
      case '2': // Lote Sul - stable
        return [
          _SampleData(
            id: '4',
            date: now.subtract(const Duration(days: 30)),
            textureClass: 'Arenosa',
            confidence: 91.2,
            depth: SamplingDepth.shallow,
            crop: Crop.available[1], // Milho
          ),
          _SampleData(
            id: '5',
            date: now.subtract(const Duration(days: 120)),
            textureClass: 'Arenosa',
            confidence: 88.7,
            depth: SamplingDepth.shallow,
            crop: Crop.available[0], // Soja
          ),
        ];
      default: // Other lots
        return [
          _SampleData(
            id: '6',
            date: now.subtract(const Duration(days: 15)),
            textureClass: 'Siltosa',
            confidence: 85.0,
            depth: SamplingDepth.shallow,
            crop: Crop.available[2], // Algodão
          ),
          _SampleData(
            id: '7',
            date: now.subtract(const Duration(days: 200)),
            textureClass: 'Média',
            confidence: 76.4,
            depth: SamplingDepth.deep,
            crop: Crop.available[3], // Cana
          ),
        ];
    }
  }
}
