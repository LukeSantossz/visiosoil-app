import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_section.dart';
import 'package:visiosoil_app/core/features/home/widgets/home_data_error.dart';
import 'package:visiosoil_app/core/features/home/widgets/last_analysis_section.dart';
import 'package:visiosoil_app/core/features/home/widgets/primary_action.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestAsync = ref.watch(latestSoilRecordProvider);
    final statsAsync = ref.watch(homeStatsProvider);

    // The stats and last-analysis sections both derive from the one records
    // stream, so a single inline error card replaces that region while the hero
    // and the capture action stay available. Read the base stream's hasError
    // directly: the derived providers wrap it with `.whenData`, which does not
    // re-expose hasError in the combined loading+error state a failed reload
    // produces, so the base stream is the reliable error signal.
    final hasError = ref.watch(soilRecordsStreamProvider).hasError;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroSection(latestAsync: latestAsync),
              PrimaryAction(onTap: () => context.push('/capture')),
              if (hasError)
                HomeDataError(
                  onRetry: () => ref.invalidate(soilRecordsStreamProvider),
                )
              else ...[
                StatsGrid(statsAsync: statsAsync),
                LastAnalysisSection(latestAsync: latestAsync),
              ],
              const SizedBox(height: 100), // bottom nav padding
            ],
          ),
        ),
      ),
    );
  }
}
