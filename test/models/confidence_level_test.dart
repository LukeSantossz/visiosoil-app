import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/models/confidence_level.dart';

void main() {
  // Thresholds per redesign v11 §3.14/§14.8: high >= 75%, moderate 50-74%,
  // low < 50%.
  test('boundary just below 50% is low', () {
    expect(ConfidenceLevel.fromScore(0.499), ConfidenceLevel.low);
  });

  test('boundary at 50% is moderate', () {
    expect(ConfidenceLevel.fromScore(0.50), ConfidenceLevel.moderate);
  });

  test('boundary just below 75% is moderate', () {
    expect(ConfidenceLevel.fromScore(0.749), ConfidenceLevel.moderate);
  });

  test('boundary at 75% is high', () {
    expect(ConfidenceLevel.fromScore(0.75), ConfidenceLevel.high);
  });

  test('moderate label reads Média, not Moderada (decision 23/10)', () {
    expect(ConfidenceLevel.moderate.label, 'Média');
  });

  test('each level exposes a solid accent color distinct from its container',
      () {
    final p = AppPalette.light;
    expect(ConfidenceLevel.high.accentColor(p), p.primary);
    expect(ConfidenceLevel.moderate.accentColor(p), p.warning);
    expect(ConfidenceLevel.low.accentColor(p), p.error);
  });

  test('moderate confidence foreground uses the onWarningContainer token', () {
    // The design system's --vs-on-warning-container; must be a named token,
    // not a raw literal, mirroring the high/low branches.
    expect(AppColors.onWarningContainer, const Color(0xFF6D4C1D));
    expect(
      ConfidenceLevel.moderate.foregroundColor(AppPalette.light),
      AppColors.onWarningContainer,
    );
  });

  test('confidence foreground/background stay on their container tokens', () {
    // In either theme, so a dark band is a dark container pair (SPEC 0107).
    for (final p in [AppPalette.light, AppPalette.dark]) {
      final reason = '${p.brightness}';
      expect(ConfidenceLevel.high.foregroundColor(p), p.onPrimaryContainer,
          reason: reason);
      expect(ConfidenceLevel.high.backgroundColor(p), p.primaryContainer,
          reason: reason);
      expect(ConfidenceLevel.moderate.foregroundColor(p), p.onWarningContainer,
          reason: reason);
      expect(ConfidenceLevel.moderate.backgroundColor(p), p.warningContainer,
          reason: reason);
      expect(ConfidenceLevel.low.foregroundColor(p), p.onErrorContainer,
          reason: reason);
      expect(ConfidenceLevel.low.backgroundColor(p), p.errorContainer,
          reason: reason);
    }
  });
}
