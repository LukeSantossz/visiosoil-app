import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// Connectivity notice with the number of analyses waiting to be sent.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.pendingCount})
    : assert(pendingCount >= 0);
  final int pendingCount;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.fromLTRB(
        (AppSpacing.lg + AppSpacing.xs),
        0,
        (AppSpacing.lg + AppSpacing.xs),
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.borderRadiusLg,
        border: context.palette.highContrast
            ? Border.all(
                color: context.palette.outline,
                width: context.density.borderWidth,
              )
            : null,
      ),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_outlined,
            color: context.palette.primaryText,
            size: 48,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Sem conexão', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${pendingCount == 1 ? '1 análise aguarda' : '$pendingCount análises aguardam'} envio. Tudo continua salvo neste aparelho.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
