import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// The history search field plus the texture-class filter chips. Owns no state:
/// the screen passes its [searchController] and the filter callbacks; the chip
/// data and the current selection are read from the providers.
class HistoryFilterBar extends ConsumerWidget {
  const HistoryFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSelectTexture,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onSelectTexture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedFilter = ref.watch(selectedTextureFilterProvider);
    final searchTerm = ref.watch(searchTermProvider);
    final availableClasses = ref.watch(availableTextureClassesProvider);

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por endereco...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: onClearSearch,
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                isDense: true,
              ),
              onChanged: onSearchChanged,
            ),
          ),
          availableClasses.when(
            loading: () => const SizedBox.shrink(),
            // Surface a load failure inline with a retry instead of silently
            // collapsing the chip bar (#117).
            error: (error, stackTrace) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.error.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Não foi possível carregar os filtros',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    // Invalidate the root records stream the chips derive from,
                    // so a transient failure actually re-runs; refreshing only
                    // the derived wrapper re-reads the same cached failed stream.
                    onPressed: () => ref.invalidate(soilRecordsStreamProvider),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
            data: (classes) {
              if (classes.isEmpty) return const SizedBox.shrink();

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Todas',
                      isSelected: selectedFilter == null,
                      onSelected: () => onSelectTexture(null),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ...classes.map((textureClass) => Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: _FilterChip(
                            label: textureClass,
                            isSelected: selectedFilter == textureClass,
                            onSelected: () => onSelectTexture(textureClass),
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primary,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: isSelected ? AppColors.primary : theme.colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primary : theme.colorScheme.outline,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      visualDensity: VisualDensity.compact,
    );
  }
}
