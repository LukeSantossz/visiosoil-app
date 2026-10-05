import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/widgets/collapse_on_correction.dart';

void main() {
  Future<void> pumpRegion(
    WidgetTester tester, {
    required bool error,
    required double height,
    bool reduceMotion = false,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduceMotion);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CollapseOnCorrection(
          isError: error,
          child: SizedBox(width: 120, height: height),
        ),
      ),
    ));
    await tester.pump();
  }

  double heightOf(WidgetTester tester) =>
      tester.getSize(find.byType(CollapseOnCorrection)).height;

  testWidgets('error_region_collapses', (tester) async {
    await pumpRegion(tester, error: true, height: 200);
    expect(heightOf(tester), 200);

    await pumpRegion(tester, error: false, height: 40);
    await tester.pump(AppMotion.base ~/ 2);

    final mid = heightOf(tester);
    expect(mid, greaterThan(40));
    expect(mid, lessThan(200));

    await tester.pump(AppMotion.base);
    expect(heightOf(tester), 40);
  });

  testWidgets('a_swap_that_is_not_a_correction_is_instant', (tester) async {
    await pumpRegion(tester, error: false, height: 200);
    await pumpRegion(tester, error: false, height: 40);
    expect(heightOf(tester), 40);

    await pumpRegion(tester, error: false, height: 40);
    await pumpRegion(tester, error: true, height: 200);
    expect(heightOf(tester), 200);
  });

  testWidgets('collapse_respects_reduced_motion', (tester) async {
    await pumpRegion(tester, error: true, height: 200, reduceMotion: true);
    await pumpRegion(tester, error: false, height: 40, reduceMotion: true);
    expect(heightOf(tester), 40);
  });
}
