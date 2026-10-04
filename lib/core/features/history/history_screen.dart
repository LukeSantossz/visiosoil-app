import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_grid.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const int _maxRecords = 150;

  final Set<int> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  /// Explicit, so the app bar's button can start a selection with nothing
  /// selected yet; a long press is not the only way in (SPEC 0122).
  bool _isSelectionMode = false;

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

  void _startEmptySelection() {
    setState(() => _isSelectionMode = true);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count $message.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (!_isSelectionMode)
            HistoryFilterBar(
              searchController: _searchController,
              onSearchChanged: _onSearchChanged,
              onClearSearch: _clearSearch,
              onSelectTexture: _selectTextureFilter,
            ),
          Expanded(
            child: HistoryGrid(
              maxRecords: _maxRecords,
              selectedIds: _selectedIds,
              isSelectionMode: _isSelectionMode,
              onTap: _handleTap,
              onLongPress: _enterSelectionMode,
            ),
          ),
        ],
      ),
    );
  }

  VisioAppBar _buildAppBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;
    // The same branches as the grid: a reload or an error keeps the previous
    // records in `value`, while the grid shows its spinner or its error.
    final hasRecords = ref.watch(filteredRecordsProvider).when(
      data: (records) => records.isNotEmpty,
      error: (error, stackTrace) => false,
      loading: () => false,
    );

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
              VisioIconButton(
                label: 'Excluir selecionados',
                icon: Icons.delete_outline,
                onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
                color: theme.colorScheme.error,
              ),
            ]
          : [
              if (hasRecords)
                VisioIconButton(
                  label: 'Selecionar registros',
                  icon: Icons.checklist,
                  onPressed: _startEmptySelection,
                ),
            ],
    );
  }

  void _handleTap(int id) {
    if (_isSelectionMode) {
      // A long press gets the platform's own vibration instead (SPEC 0126).
      AppHaptics.selection();
      _toggleSelection(id);
    } else {
      // Details first; its photograph opens the viewer (SPEC 0125).
      context.push('/details', extra: id);
    }
  }
}
