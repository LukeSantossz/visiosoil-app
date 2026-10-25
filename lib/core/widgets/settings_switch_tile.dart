import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';

/// A settings row with a trailing switch (redesign v11 §4 `SettingsSwitchTile`):
/// [title] and an optional [subtitle], tapping anywhere in the row toggles
/// [value]. Disabled (and visibly dimmed) when [onChanged] is null.
///
/// Plays [AppHaptics.selection] on toggle when [haptic] (default): most
/// toggles use the selection tier (redesign v11 §7); a caller whose own
/// toggle plays a different tier (e.g. turning Vibração itself on, which
/// samples with [AppHaptics.confirm]) passes `haptic: false` and fires its
/// own haptic after committing the preference.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.haptic = true,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the tile.
  final ValueChanged<bool>? onChanged;
  final bool haptic;

  bool get _enabled => onChanged != null;

  void _toggle() {
    if (!_enabled) return;
    if (haptic) AppHaptics.selection();
    onChanged!(!value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;

    return Semantics(
      toggled: value,
      enabled: _enabled,
      label: subtitle != null ? '$title. $subtitle' : title,
      onTap: _enabled ? _toggle : null,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: _enabled ? _toggle : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: palette.primaryText),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: theme.textTheme.bodyLarge),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: palette.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Thumb(value: value, enabled: _enabled),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The animated switch itself: track color and thumb size/position tween
/// over [AppMotion.base] with the emphasized curve, approximating the mock's
/// spring (redesign v11 §4: "mola do thumb").
class _Thumb extends StatelessWidget {
  const _Thumb({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final duration = AppMotion.durationOf(context, AppMotion.base);
    final switchTheme = Theme.of(context).switchTheme;
    final states = <WidgetState>{if (value) WidgetState.selected};
    final track = palette.isSun
        ? switchTheme.trackColor?.resolve(states)
        : null;
    final thumb = palette.isSun
        ? switchTheme.thumbColor?.resolve(states)
        : null;

    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.standard,
        width: 52,
        height: 32,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color:
              track ?? (value ? palette.primary : palette.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: palette.isSun
                ? Colors.black
                : (value ? palette.primary : palette.outline),
            width: 2,
          ),
        ),
        child: AnimatedAlign(
          duration: duration,
          curve: AppMotion.emphasized,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.emphasized,
            width: value ? 24 : 16,
            height: value ? 24 : 16,
            decoration: BoxDecoration(
              color: thumb ?? (value ? palette.onPrimary : palette.outline),
              shape: BoxShape.circle,
            ),
            child: value
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: palette.isSun ? Colors.black : palette.primary,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
