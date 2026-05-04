import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestAsync = ref.watch(latestSoilRecordProvider);
    final recordsAsync = ref.watch(soilRecordsStreamProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroSection(latestAsync: latestAsync),
              _PrimaryAction(onTap: () => context.push('/capture')),
              _StatsGrid(recordsAsync: recordsAsync),
              _LastAnalysisSection(latestAsync: latestAsync),
              // Placeholder for lot map (future feature)
              _LotMapPlaceholder(),
              const SizedBox(height: 100), // bottom nav padding
            ],
          ),
        ),
      ),
    );
  }
}

// --- Hero Section ---
class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.latestAsync});

  final AsyncValue<SoilRecord?> latestAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = latestAsync.value;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.5, -1),
          end: Alignment(0.8, 1),
          colors: [AppColors.primaryContainer, AppColors.tertiaryContainer],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.xl),
          bottomRight: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: logo + settings
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: AppRadius.borderRadiusMd,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D4A7C59),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.layers, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VisioSoil',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F1A1C19),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Greeting
          Text(
            _greeting(),
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          if (latest != null && latest.hasClassification) ...[
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: 'Última análise: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                children: [
                  TextSpan(
                    text: latest.displayTextureClass,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: ', ${latest.formattedTimestampCompact}',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia.';
    if (hour < 18) return 'Boa tarde.';
    return 'Boa noite.';
  }
}

// --- Primary Action Button ---
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Material(
        color: AppColors.onSurface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              boxShadow: const [
                BoxShadow(
                  color: Color(0x331A1C19),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nova análise',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Foto + localização → classe + plano',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Stats Grid ---
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.recordsAsync});

  final AsyncValue<List<SoilRecord>> recordsAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = recordsAsync.value ?? [];
    final total = records.length;
    final locations = records.where((r) => r.hasValidAddress).map((r) => r.address).toSet().length;
    final scored = records.where((r) => r.confidenceScore != null).toList();
    final avgConfidence = scored.isEmpty
        ? null
        : scored.fold<double>(0, (sum, r) => sum + r.confidenceScore!) / scored.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          _StatCard(
            value: '$total',
            label: 'Análises',
            icon: Icons.layers,
            color: AppColors.primary,
            theme: theme,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            value: '$locations',
            label: 'Locais',
            icon: Icons.map_outlined,
            color: AppColors.secondary,
            theme: theme,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            value: avgConfidence == null ? '-' : '${(avgConfidence * 100).round()}%',
            label: 'Confiança',
            icon: Icons.track_changes,
            color: AppColors.tertiary,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.theme,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.borderRadiusLg,
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A1A1C19),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Last Analysis Section ---
class _LastAnalysisSection extends ConsumerWidget {
  const _LastAnalysisSection({required this.latestAsync});

  final AsyncValue<SoilRecord?> latestAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final record = latestAsync.value;

    if (record == null) return const SizedBox.shrink();

    final imageFile = File(record.imagePath);
    final textureColor = record.hasClassification
        ? SoilTextureColors.forClass(record.textureClass!)
        : AppColors.outline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÚLTIMA ANÁLISE',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: record.id != null
                ? () => context.push('/details', extra: record.id!)
                : null,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.borderRadiusLg,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A1A1C19),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
                border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // Thumbnail
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: Image.file(
                      imageFile,
                      fit: BoxFit.cover,
                      cacheWidth: 252,
                      errorBuilder: (_, _, _) => Container(
                        color: textureColor.withValues(alpha: 0.3),
                        child: Icon(
                          Icons.landscape,
                          color: textureColor,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                record.displayTextureClass,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (record.confidenceScore != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer,
                                    borderRadius: AppRadius.borderRadiusPill,
                                  ),
                                  child: Text(
                                    record.formattedConfidence,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onPrimaryContainer,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            record.formattedTimestampCompact,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                'Ver detalhes',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward,
                                size: 11,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Lot Map Placeholder ---
class _LotMapPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SEUS LOTES',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.onSurface,
                ),
              ),
              // Future: "Novo lote" button
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 140,
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusLg,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.tertiaryContainer,
                  AppColors.secondaryContainer,
                  AppColors.surfaceVariant,
                ],
              ),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.map_outlined,
                    size: 32,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mapa de lotes em breve',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
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
}
