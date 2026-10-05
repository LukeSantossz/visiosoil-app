import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
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
                hintText: 'Buscar por endereço...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: searchTerm.isNotEmpty
                    ? VisioIconButton(
                        label: 'Limpar busca',
                        icon: Icons.clear,
                        iconSize: 20,
                        onPressed: onClearSearch,
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
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
              // At large text the retry's label wraps within half the row
              // instead of squeezing the message (SPEC 0121).
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: context.palette.error.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Não foi possível carregar os filtros',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth / 2),
                      child: TextButton(
                        // Invalidate the root records stream the chips derive
                        // from, so a transient failure actually re-runs;
                        // refreshing only the derived wrapper re-reads the same
                        // cached failed stream.
                        onPressed: () =>
                            ref.invalidate(soilRecordsStreamProvider),
                        child: const Text('Tentar novamente'),
                      ),
                    ),
                  ],
                ),
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
    final unselectedLabel = theme.colorScheme.onSurface;
    final selectedLabel = context.palette.primary;
    final unselectedBorder = theme.colorScheme.outline;

    // The chip's own side animates over 75 ms inside Material. The catalogue
    // wants 140 ms, so the line is drawn in front and the chip draws none.
    // shrinkWrap keeps that line on the material; the slot keeps the padded
    // tap target the default chip had (SPEC 0137).
    final adjustment = VisualDensity.compact.baseSizeAdjustment;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: isSelected ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.fast,
      curve: AppMotion.standard,
      builder: (context, t, _) {
        return _ChipSlot(
          minTarget: Size(
            kMinInteractiveDimension + adjustment.dx,
            kMinInteractiveDimension + adjustment.dy,
          ),
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusSm,
              border: Border.all(
                color: Color.lerp(unselectedBorder, selectedLabel, t)!,
              ),
            ),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                AppHaptics.selection();
                onSelected();
              },
              selectedColor: selectedLabel.withValues(alpha: 0.2),
              checkmarkColor: selectedLabel,
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: Color.lerp(unselectedLabel, selectedLabel, t),
                fontWeight: FontWeight.lerp(
                  FontWeight.normal,
                  FontWeight.w600,
                  t,
                ),
              ),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.borderRadiusSm,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      },
    );
  }
}

/// Centres a shrink-wrapped chip in the padded target [FilterChip] would have
/// used, and sends a tap in that padding to the chip.
class _ChipSlot extends SingleChildRenderObjectWidget {
  const _ChipSlot({required this.minTarget, required super.child});

  final Size minTarget;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderChipSlot(minTarget);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderChipSlot renderObject,
  ) {
    renderObject.minTarget = minTarget;
  }
}

class _RenderChipSlot extends RenderShiftedBox {
  _RenderChipSlot(this._minTarget) : super(null);

  Size _minTarget;

  set minTarget(Size value) {
    if (value == _minTarget) return;
    _minTarget = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final box = child!;
    box.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        box.size.width > _minTarget.width ? box.size.width : _minTarget.width,
        box.size.height > _minTarget.height
            ? box.size.height
            : _minTarget.height,
      ),
    );
    (box.parentData! as BoxParentData).offset = Offset(
      (size.width - box.size.width) / 2,
      (size.height - box.size.height) / 2,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final box = child;
    if (box == null) return false;
    final data = box.parentData! as BoxParentData;
    final local = position - data.offset;
    final inside = box.size.contains(local);
    final hit = inside
        ? local
        : Offset(
            local.dx.clamp(0.0, box.size.width).toDouble(),
            box.size.height / 2,
          );
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset _) {
        return box.hitTest(result, position: hit);
      },
    );
  }
}
