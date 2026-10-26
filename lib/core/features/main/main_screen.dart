import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/home/home_screen.dart';
import 'package:visiosoil_app/core/features/main/lost_capture_recovery.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/features/profile/profile_screen.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import 'package:visiosoil_app/providers/main_tab_index_provider.dart';

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  static const List<Widget> _screens = [
    HomeScreen(),
    HistoryScreen(),
    _TipsTab(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(mainTabIndexProvider);

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && currentIndex != 0) {
          ref.read(mainTabIndexProvider.notifier).select(0);
        }
      },
      child: LostCaptureRecovery(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabs = IndexedStack(index: currentIndex, children: _screens);
            void select(int index) {
              AppHaptics.selection();
              ref.read(mainTabIndexProvider.notifier).select(index);
            }

            // A rail from 600 dp, the bar below (redesign v11 §10).
            if (constraints.maxWidth >= 600) {
              return Scaffold(
                body: Row(
                  children: [
                    SafeArea(
                      right: false,
                      child: NavigationRail(
                        // Four destinations stay reachable in a short window.
                        scrollable: true,
                        selectedIndex: currentIndex,
                        onDestinationSelected: select,
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final d in _destinations)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: Text(d.label),
                            ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: tabs),
                  ],
                ),
              );
            }
            return Scaffold(
              body: tabs,
              bottomNavigationBar: NavigationBar(
                selectedIndex: currentIndex,
                onDestinationSelected: select,
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

const _destinations = [
  (icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Início'),
  (
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library,
    label: 'Histórico',
  ),
  (
    icon: Icons.lightbulb_outline,
    selectedIcon: Icons.lightbulb_outline,
    label: 'Dicas',
  ),
  (
    icon: Icons.person_outline,
    selectedIcon: Icons.person_outline,
    label: 'Perfil',
  ),
];

/// Reuses the existing record-based tips instead of inventing sample advice.
class _TipsTab extends ConsumerWidget {
  const _TipsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(latestClassifiedSoilRecordProvider);
    return SafeArea(
      child: record.when(
        loading: () => const Center(child: LoadingIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não foi possível carregar as dicas.')),
        data: (value) => value == null
            ? const Center(child: Text('Sem dicas para esta classe ainda.'))
            : SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ManagementTipsSection(record: value),
                  ),
                ),
              ),
      ),
    );
  }
}
