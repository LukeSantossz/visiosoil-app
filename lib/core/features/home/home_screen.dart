import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_section.dart';
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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroSection(latestAsync: latestAsync),
              PrimaryAction(onTap: () => context.push('/capture')),
              StatsGrid(statsAsync: statsAsync),
              LastAnalysisSection(latestAsync: latestAsync),
              const SizedBox(height: 100), // bottom nav padding
            ],
          ),
        ),
      ),
    );
  }
}
