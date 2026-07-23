import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The home dashboard header: a brand bar, a time-of-day greeting, and (when a
/// classified record exists) a one-line "última análise" summary, over the
/// primary→tertiary gradient.
class HeroSection extends StatelessWidget {
  const HeroSection({super.key, required this.latestAsync});

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
          _HeroTopBar(onOpenSettings: () => context.push('/settings')),
          const SizedBox(height: 14),
          Text(
            _greeting(),
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          if (latest != null && latest.hasClassification) ...[
            const SizedBox(height: 4),
            _LastAnalysisLine(latest: latest),
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

/// Brand logo + title on the left, settings entry point on the right.
class _HeroTopBar extends StatelessWidget {
  const _HeroTopBar({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: AppRadius.borderRadiusMd,
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowBrand,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.layers, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'VisioSoil',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowControl,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: IconButton(
            onPressed: onOpenSettings,
            padding: EdgeInsets.zero,
            iconSize: 17,
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Última análise: texture class, timestamp" line under the greeting.
class _LastAnalysisLine extends StatelessWidget {
  const _LastAnalysisLine({required this.latest});

  final SoilRecord latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text.rich(
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
          TextSpan(text: ', ${latest.formattedTimestampCompact}'),
        ],
      ),
    );
  }
}
