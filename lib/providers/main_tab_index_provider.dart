import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected bottom-navigation tab on [MainScreen] (0 = Início, 1 = Histórico).
///
/// Shared so home content can switch tabs — the "Ver tudo" link on the home's
/// last-analysis section opens the History tab, which has no pushable route.
class MainTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Selects a tab by index.
  void select(int index) => state = index;
}

/// Current [MainScreen] tab index.
final mainTabIndexProvider =
    NotifierProvider<MainTabIndexNotifier, int>(MainTabIndexNotifier.new);
