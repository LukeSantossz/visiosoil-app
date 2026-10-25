import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Shared anonymous/linked identity header; callers supply account actions.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, this.name, this.email, required this.child});

  final String? name;
  final String? email;
  final Widget child;

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg + AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: '$title, $subtitle',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: email == null
                          ? context.palette.surfaceContainer
                          : context.palette.primaryContainer,
                      child: email == null
                          ? Icon(
                              Icons.person_outline,
                              color: context.palette.onSurfaceVariant,
                            )
                          : Text(
                              initials,
                              style: TextStyle(
                                color: context.palette.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: context.palette.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}
