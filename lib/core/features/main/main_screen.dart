import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/home/home_screen.dart';
import 'package:visiosoil_app/core/features/main/lost_capture_recovery.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
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
              // A rule on top of the bar (PNG 08, SPEC 0203).
              bottomNavigationBar: DecoratedBox(
                key: const Key('navigation-bar-rule'),
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: context.palette.divider,
                      width: context.palette.edgeWidth,
                    ),
                  ),
                ),
                child: NavigationBar(
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
              ),
            );
          },
        ),
      ),
    );
  }
}

// Lucide, as the mocks draw them (redesign v11 §5, SPEC 0201).
const _destinations = [
  (icon: LucideIcons.house, selectedIcon: LucideIcons.house, label: 'Início'),
  (
    icon: LucideIcons.history,
    selectedIcon: LucideIcons.history,
    label: 'Histórico',
  ),
  (
    icon: LucideIcons.lightbulb,
    selectedIcon: LucideIcons.lightbulb,
    label: 'Dicas',
  ),
  (icon: LucideIcons.user, selectedIcon: LucideIcons.user, label: 'Perfil'),
];

/// Reuses the existing record-based tips instead of inventing sample advice.
/// The tab has its app bar, whose back selects Início as the system back
/// does, and 16 dp margins (PNG 20, SPEC 0205).
class _TipsTab extends ConsumerWidget {
  const _TipsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(latestClassifiedSoilRecordProvider);
    return Scaffold(
      appBar: VisioAppBar(
        title: 'Dicas de manejo',
        leading: VisioIconButton(
          label: 'Voltar',
          icon: LucideIcons.arrowLeft,
          onPressed: () => ref.read(mainTabIndexProvider.notifier).select(0),
        ),
      ),
      body: record.when(
        loading: () => const Center(child: LoadingIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não foi possível carregar as dicas.')),
        data: (value) => value == null
            ? const Center(child: Text('Sem dicas para esta classe ainda.'))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ManagementTipsSection(record: value, asPage: true),
                  ),
                ),
              ),
      ),
    );
  }
}
