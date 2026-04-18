import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/empty_state.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const int _maxRecords = 150;

  final Set<int> _selectedIds = {};

  bool get _isSelectionMode => _selectedIds.isNotEmpty;

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

    if (confirmed == true && mounted) {
      await _performDeletion();
      _showDeletionSnackbar(count);
    }
  }

  Future<bool?> _showDeleteConfirmation(int count) {
    final itemLabel = count == 1 ? 'registro' : 'registros';

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir registros'),
        content: Text(
          'Tem certeza que deseja excluir $count $itemLabel? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeletion() async {
    final ids = _selectedIds.toList();
    await ref.read(soilRecordRepositoryProvider).deleteByIds(ids);
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
      body: _HistoryGrid(
        maxRecords: _maxRecords,
        selectedIds: _selectedIds,
        isSelectionMode: _isSelectionMode,
        onTap: _handleTap,
        onLongPress: _enterSelectionMode,
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

class _HistoryGrid extends ConsumerWidget {
  const _HistoryGrid({
    required this.maxRecords,
    required this.selectedIds,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final int maxRecords;
  final Set<int> selectedIds;
  final bool isSelectionMode;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecords = ref.watch(soilRecordsStreamProvider);

    return asyncRecords.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Não foi possível carregar o histórico.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return _EmptyHistoryState();
        }
        return _buildGrid(records);
      },
    );
  }

  Widget _buildGrid(List<SoilRecord> records) {
    final visible = records.length > maxRecords
        ? records.sublist(0, maxRecords)
        : records;

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 1,
      ),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final record = visible[index];
        final id = record.id!;

        return _ThumbnailCard(
          record: record,
          isSelected: selectedIds.contains(id),
          isSelectionMode: isSelectionMode,
          onTap: () => onTap(id),
          onLongPress: () => onLongPress(id),
        );
      },
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.photo_library_outlined,
      title: 'Nenhum registro',
      description: 'Capture sua primeira amostra de solo para começar.',
      action: VisioButton(
        label: 'Nova Captura',
        icon: Icons.camera_alt,
        onPressed: () => context.push('/capture'),
      ),
    );
  }
}

class _ThumbnailCard extends StatelessWidget {
  const _ThumbnailCard({
    required this.record,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final SoilRecord record;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ThumbnailImage(imagePath: record.imagePath),
            _GradientOverlay(),
            _TimestampLabel(timestamp: record.formattedTimestampCompact),
            if (isSelectionMode) _SelectionOverlay(isSelected: isSelected),
            if (isSelectionMode) _SelectionCheckbox(isSelected: isSelected),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageFile = File(imagePath);

    return Image.file(
      imageFile,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: frame != null
              ? child
              : Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.image,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.broken_image, color: theme.colorScheme.error),
          ),
        );
      },
    );
  }
}

class _GradientOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          ),
        ),
      ),
    );
  }
}

class _TimestampLabel extends StatelessWidget {
  const _TimestampLabel({required this.timestamp});

  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      left: AppSpacing.sm,
      right: AppSpacing.sm,
      bottom: AppSpacing.sm,
      child: Text(
        timestamp,
        style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _SelectionOverlay extends StatelessWidget {
  const _SelectionOverlay({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned.fill(
      child: Container(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.3)
            : Colors.transparent,
      ),
    );
  }
}

class _SelectionCheckbox extends StatelessWidget {
  const _SelectionCheckbox({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      top: AppSpacing.sm,
      right: AppSpacing.sm,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
            width: 2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
