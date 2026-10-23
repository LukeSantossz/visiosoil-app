import 'package:flutter/services.dart';

/// Haptic tiers mirroring the microinteraction strategy
/// (`docs/design/ux-2026/09-microinteractions.md` §5, SPEC 0126, redesign v11 §7).
///
/// Haptics confirm, they do not decorate: one tier per class of event.
/// [selection] for a chip, tab or list choice; [confirm] for the photograph
/// returning and a record saved; [result] for a classification arriving.
/// The heavy tier ([blocked]) is used only for the bad-photo path (redesign v11
/// §7, decision 14.7). A long press needs none of these, since Flutter already
/// vibrates for it on Android.
abstract final class AppHaptics {
  /// When false, all haptic methods return immediately without vibrating.
  /// Bound to the Vibration toggle in Settings (redesign v11 §3.11).
  static bool enabled = true;

  static Future<void> selection() async {
    if (enabled) await HapticFeedback.selectionClick();
  }

  static Future<void> confirm() async {
    if (enabled) await HapticFeedback.lightImpact();
  }

  static Future<void> result() async {
    if (enabled) await HapticFeedback.mediumImpact();
  }

  /// Heavy double-impact for a blocked photo capture (redesign v11 §7).
  /// Two heavy impacts 60 ms apart.
  static Future<void> blocked() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.heavyImpact();
  }

  /// Linked-account sequence (redesign v11 §7): medium then light, 90 ms apart.
  static Future<void> linked() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.lightImpact();
  }
}
