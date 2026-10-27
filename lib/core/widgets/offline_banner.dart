import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

/// Connectivity notice with the number of analyses waiting to be sent, as
/// PNG 18 draws it (SPEC 0214).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.pendingCount})
    : assert(pendingCount >= 0);
  final int pendingCount;
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Container(
          key: const ValueKey('offline-card'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 43, 20, 23.5),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: AppRadius.borderRadiusLg,
            border: palette.highContrast
                ? Border.all(
                    color: palette.outline,
                    width: context.density.borderWidth,
                  )
                : null,
          ),
          child: Column(
            children: [
              ExcludeSemantics(
                child: CustomPaint(
                  key: const ValueKey('offline-art'),
                  size: const Size(64, 50),
                  painter: _OfflineArt(
                    ink: palette.isSun
                        ? palette.onSurface
                        : palette.primaryText,
                    bar: palette.isSun
                        ? palette.onSurface
                        : palette.textTertiary,
                    slash: palette.error,
                  ),
                ),
              ),
              const SizedBox(height: 23.5),
              Text(
                'Sem conexão',
                textAlign: TextAlign.center,
                style: AppTypography.weighted(
                  AppTypography.resized(text.titleMedium!, 15, height: 20 / 15),
                  400,
                ).copyWith(color: palette.onSurface),
              ),
              const SizedBox(height: 4.5),
              Text(
                '${pendingCount == 1 ? '1 análise aguarda' : '$pendingCount análises aguardam'} envio. Tudo continua salvo neste aparelho.',
                textAlign: TextAlign.center,
                style: AppTypography.resized(
                  text.bodySmall!,
                  13,
                  height: 18.5 / 13,
                ).copyWith(color: palette.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// PNG 18's phone holding soil grains beside a struck-through Wi-Fi, at the
/// coordinates measured on it (SPEC 0214).
class _OfflineArt extends CustomPainter {
  const _OfflineArt({
    required this.ink,
    required this.bar,
    required this.slash,
  });

  final Color ink;
  final Color bar;
  final Color slash;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = ink
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2.6, 0.75, 27.5, 47.75),
        const Radius.circular(4),
      ),
      stroke..strokeWidth = 1.25,
    );
    final fill = Paint()..color = ink;
    for (final (x, y, r) in const [
      (12.4, 19.75, 2.0),
      (19.5, 21.9, 1.4),
      (15.5, 27.9, 1.25),
      (21.0, 28.9, 0.75),
    ]) {
      canvas.drawCircle(Offset(x, y), r, fill);
    }
    canvas.drawLine(
      const Offset(12.6, 43.9),
      const Offset(20.4, 43.9),
      Paint()
        ..color = bar
        ..strokeWidth = 0.75,
    );
    const centre = Offset(52, 27);
    const up = -1.5707963267948966;
    for (final (radius, half) in const [(19.5, 0.663), (11.5, 0.785)]) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        up - half,
        2 * half,
        false,
        stroke..strokeWidth = 1,
      );
    }
    canvas.drawCircle(const Offset(52, 25), 1.4, fill);
    canvas.drawLine(
      const Offset(40.75, 2.6),
      const Offset(63, 29.1),
      Paint()
        ..color = slash
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_OfflineArt oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.bar != bar ||
      oldDelegate.slash != slash;
}
