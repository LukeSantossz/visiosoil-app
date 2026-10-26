import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

/// Shared anonymous/linked identity header; callers supply account actions.
class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    this.name,
    this.email,
    required this.child,
    this.bottomPadding = AppSpacing.lg + AppSpacing.xs,
  });

  final String? name;
  final String? email;
  final Widget child;

  /// Less than the card's 20 dp when [child] ends in a row whose 48 dp
  /// target reaches past its visible content (PNG 22).
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final title = name ?? email ?? 'Sem conta vinculada';
    final subtitle = email ?? 'Dados só neste aparelho';
    final initials = title
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    final theme = Theme.of(context);
    final palette = context.palette;
    // Flat on `surface`, radius 24 and 20 dp in; a 56 dp avatar, the 18 sp
    // title 14 dp after it (PNG 21 and 22, SPEC 0204).
    return Container(
      key: const Key('account-card'),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg + AppSpacing.xs,
        AppSpacing.lg + AppSpacing.xs,
        AppSpacing.lg + AppSpacing.xs,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        border: palette.highContrast
            ? Border.all(color: palette.cardBorder, width: palette.edgeWidth)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            label: '$title, $subtitle',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Container(
                    key: const Key('account-avatar'),
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: email == null
                          ? palette.surfaceContainer.withValues(alpha: .5)
                          : palette.primaryContainer,
                    ),
                    child: email == null
                        ? Icon(
                            LucideIcons.user,
                            size: 28,
                            color: palette.onSurfaceVariant,
                          )
                        // 20 sp weight 650 in `primaryText` (PNG 22).
                        : Text(
                            initials,
                            style: AppTypography.weighted(
                              AppTypography.resized(
                                theme.textTheme.titleMedium!,
                                20,
                                height: 1,
                              ),
                              650,
                            ).copyWith(color: palette.primaryText),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.resized(
                            theme.textTheme.titleMedium!,
                            18,
                            height: 24 / 18,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: email == null ? null : 1,
                          overflow: email == null
                              ? null
                              : TextOverflow.ellipsis,
                          softWrap: email == null ? null : false,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
