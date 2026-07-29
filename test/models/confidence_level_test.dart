import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/models/confidence_level.dart';

void main() {
  test('moderate confidence foreground uses the onWarningContainer token', () {
    // The design system's --vs-on-warning-container; must be a named token,
    // not a raw literal, mirroring the high/low branches.
    expect(AppColors.onWarningContainer, const Color(0xFF6D4C1D));
    expect(
      ConfidenceLevel.moderate.foregroundColor,
      AppColors.onWarningContainer,
    );
  });

  test('confidence foreground/background stay on their container tokens', () {
    expect(ConfidenceLevel.high.foregroundColor, AppColors.onPrimaryContainer);
    expect(ConfidenceLevel.high.backgroundColor, AppColors.primaryContainer);
    expect(ConfidenceLevel.moderate.backgroundColor, AppColors.warningContainer);
    expect(ConfidenceLevel.low.foregroundColor, AppColors.onErrorContainer);
    expect(ConfidenceLevel.low.backgroundColor, AppColors.errorContainer);
  });
}
