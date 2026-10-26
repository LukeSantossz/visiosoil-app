import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_list.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const int _pageSize = 150;

  final Set<int> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  /// A row's long press or its "Selecionar" semantics action starts it, so a
  /// gesture is not the only way in (SPEC 0122, SPEC 0203). Deselecting the
  /// last record ends it.
  bool _isSelectionMode = false;

  /// The app bar's search and filter actions open their part of the filter
  /// bar; a part also stays open while it holds a term or a class (PNG 16,
  /// SPEC 0203).
  bool _searchOpen = false;
  bool _filtersOpen = false;

  /// The record open beside the list from 840 dp (redesign v11 §10,
  /// SPEC 0200). Below that, a tap pushes details instead.
  int? _activeId;
  bool _masterDetail = false;

  @override
  void initState() {
    super.initState();
    // Syncs the controller with the persisted provider (e.g. after navigation)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentTerm = ref.read(searchTermProvider);
      if (currentTerm.isNotEmpty && _searchController.text != currentTerm) {
        _searchController.text = currentTerm;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchTermProvider.notifier).update(value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(searchTermProvider.notifier).update('');
  }

  void _selectTextureFilter(String? textureClass) {
    ref.read(selectedTextureFilterProvider.notifier).select(textureClass);
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        // Deselecting the last record ends the mode, as it always has.
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(int id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await _showDeleteConfirmation(count);

    if (confirmed && mounted) {
      await _performDeletion();
      _showDeletionSnackbar(count);
    }
  }

  Future<bool> _showDeleteConfirmation(int count) {
    final itemLabel = count == 1 ? 'registro' : 'registros';

    return confirmDestructiveAction(
      context,
      title: 'Excluir registros',
      message:
          'Tem certeza que deseja excluir $count $itemLabel? Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir',
    );
  }

  Future<void> _performDeletion() async {
    final ids = _selectedIds.toList();
    await ref.read(soilRecordRepositoryProvider).deleteByIds(ids);
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _showDeletionSnackbar(int count) {
    if (!mounted) return;

    final message = count == 1 ? 'registro excluído' : 'registros excluídos';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$count $message.')));
  }

  @override
  Widget build(BuildContext context) {
    final shown = ref.watch(filteredRecordsProvider).value ?? const [];
    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The window's width, so the rail beside the tabs does not move
            // the breakpoint; the panes then share the width left.
            _masterDetail = MediaQuery.sizeOf(context).width >= 840;
            final list = Column(
              children: [
                if (!_isSelectionMode)
                  HistoryFilterBar(
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: _clearSearch,
                    onSelectTexture: _selectTextureFilter,
                    showSearch:
                        _searchOpen || ref.watch(searchTermProvider).isNotEmpty,
                    showFilters:
                        _filtersOpen ||
                        ref.watch(selectedTextureFilterProvider) != null,
                  ),
                Expanded(
                  child: HistoryList(
                    pageSize: _pageSize,
                    selectedIds: _selectedIds,
                    isSelectionMode: _isSelectionMode,
                    onTap: _handleTap,
                    onLongPress: _enterSelectionMode,
                    onSelect: _enterSelectionMode,
                    activeId: _masterDetail ? _activeId : null,
                  ),
                ),
              ],
            );
            if (!_masterDetail) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: list,
                ),
              );
            }
            return Row(
              children: [
                SizedBox(width: 360, child: list),
                const VerticalDivider(width: 1),
                Expanded(child: _detailPane(shown)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The chosen record, or the placeholder until one is chosen and once it
  /// leaves the list, deleted or filtered out.
  Widget _detailPane(List<SoilRecord> shown) {
    final id = _activeId;
    if (id == null || !shown.any((record) => record.id == id)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'Selecione uma análise para ver os detalhes.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return DetailsScreen(key: ValueKey(id), recordId: id);
  }

  VisioAppBar _buildAppBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;

    return VisioAppBar(
      title: switch ((_isSelectionMode, count)) {
        (false, _) => 'Histórico',
        (true, 0) => 'Nenhum selecionado',
        (true, _) => '$count selecionado${count > 1 ? 's' : ''}',
      },
      leading: _isSelectionMode
          ? VisioIconButton(
              label: 'Cancelar seleção',
              icon: Icons.close,
              onPressed: _cancelSelection,
            )
          : null,
      actions: _isSelectionMode
          ? [
              // Exactly two: the comparison sets one record beside another
              // (SPEC 0150).
              VisioIconButton(
                label: 'Comparar selecionados',
                icon: Icons.compare_arrows,
                onPressed: count == 2
                    ? () =>
                          context.push('/compare', extra: _selectedIds.toList())
                    : null,
              ),
              VisioIconButton(
                label: 'Excluir selecionados',
                icon: Icons.delete_outline,
                onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
                color: theme.colorScheme.error,
              ),
            ]
          : [
              // Search and filters, as PNG 16 draws the bar (SPEC 0203). A
              // selection starts from a row: a long press, or its
              // "Selecionar" semantics action.
              VisioIconButton(
                label: 'Buscar',
                icon: LucideIcons.search,
                onPressed: () => setState(() => _searchOpen = !_searchOpen),
              ),
              const SizedBox(width: AppSpacing.xs),
              VisioIconButton(
                label: 'Filtros',
                icon: LucideIcons.slidersHorizontal,
                onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
    );
  }

  void _handleTap(int id) {
    if (_isSelectionMode) {
      // A long press gets the platform's own vibration instead (SPEC 0126).
      AppHaptics.selection();
      _toggleSelection(id);
    } else {
      if (_masterDetail) {
        setState(() => _activeId = id);
      } else {
        // Details first; its photograph opens the viewer (SPEC 0125).
        context.push('/details', extra: id);
      }
    }
  }
}
