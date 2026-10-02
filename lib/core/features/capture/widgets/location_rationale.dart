import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// One line, shown before a capture while location is not granted, saying why
/// the capture will ask for it (SPEC 0099). Android's location dialog carries
/// no word from the app; iOS already shows `NSLocationWhenInUseUsageDescription`.
class LocationRationale extends StatefulWidget {
  const LocationRationale({super.key, this.checkPermission});

  static const String message =
      'A localização do aparelho marca onde a amostra foi coletada. '
      'Sem ela, o registro é salvo sem coordenadas.';

  /// Reads the location permission; defaults to
  /// [PermissionService.checkLocation]. Injected so tests can answer without
  /// the platform plugin.
  final Future<AppPermissionStatus> Function()? checkPermission;

  @override
  State<LocationRationale> createState() => _LocationRationaleState();
}

class _LocationRationaleState extends State<LocationRationale> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final check = widget.checkPermission ?? PermissionService.checkLocation;
    final AppPermissionStatus status;
    try {
      status = await check();
    } catch (_) {
      // An unreadable status shows nothing rather than a claim the app cannot
      // back.
      return;
    }
    if (!mounted || status == AppPermissionStatus.granted) return;
    setState(() => _show = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        LocationRationale.message,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.palette.onSurfaceVariant),
      ),
    );
  }
}
