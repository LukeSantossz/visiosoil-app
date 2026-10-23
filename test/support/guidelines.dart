import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

/// The app's light and dark themes, by name, for a test run once in each.
final List<(String, ThemeData)> appThemes = [
  ('light', AppTheme.light),
  ('dark', AppTheme.dark),
];

/// Holds the screen in view to Flutter's four accessibility guidelines: each
/// platform's minimum tap target, a label on every tap target, and text
/// contrast (SPEC 0133). Semantics must be on, through `ensureSemantics`.
Future<void> expectMeetsGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Modo Sol's own, stricter tap target: 56 dp instead of the platform's 48
/// (redesign v11 §1.4, SPEC 0182).
const AccessibilityGuideline sunTapTargetGuideline = MinimumTapTargetGuideline(
  size: Size(56, 56),
  link: 'https://m3.material.io/foundations/accessible-design/'
      'accessibility-basics',
);
