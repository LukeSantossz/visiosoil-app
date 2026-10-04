import 'package:flutter/services.dart';

/// Haptic tiers mirroring the microinteraction strategy
/// (`docs/design/ux-2026/09-microinteractions.md` §5, SPEC 0126).
///
/// Haptics confirm, they do not decorate: one tier per class of event.
/// [selection] for a chip, tab or list choice; [confirm] for the photograph
/// returning and a record saved; [result] for a classification arriving.
/// There is deliberately no heavy tier: nothing in this product is that
/// important. A long press needs none of these, since Flutter already
/// vibrates for it on Android.
abstract final class AppHaptics {
  static Future<void> selection() => HapticFeedback.selectionClick();

  static Future<void> confirm() => HapticFeedback.lightImpact();

  static Future<void> result() => HapticFeedback.mediumImpact();
}
