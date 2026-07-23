import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_grid.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';
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

  bool get _isSelectionMode => _selectedIds.isNotEmpty;

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
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(int id) {
    setState(() => _selectedIds.add(id));
  }

  void _cancelSelection() {
    setState(() => _selectedIds.clear());
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
    setState(() => _selectedIds.clear());
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

  AppBar _buildAppBar() {
    final theme = Theme.of(context);
    final count = _selectedIds.length;

    return AppBar(
      title: Text(_isSelectionMode
          ? '$count selecionado${count > 1 ? 's' : ''}'
          : 'Histórico'),
      centerTitle: true,
      leading: _isSelectionMode
          ? IconButton(icon: const Icon(Icons.close), onPressed: _cancelSelection)
          : null,
      actions: _isSelectionMode
          ? [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
                color: theme.colorScheme.error,
              ),
            ]
          : null,
    );
  }

  void _handleTap(int id) {
    if (_isSelectionMode) {
      _toggleSelection(id);
    } else {
      context.push('/preview', extra: id);
    }
  }
}
