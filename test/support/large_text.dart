import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Puts [tester] on a 411 × 891 dp phone (1080 × 2340 px at 2.625) with the
/// font size at 200 %, the scale a screen must still lay out at (SPEC 0121).
/// A layout overflow is reported as a `FlutterError`, which fails the test.
void useLargeTextOnAPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Drags the screen's first vertical scrollable to its end, a step at a time,
/// so a lazy list lays out every row it holds.
Future<void> scrollToTheEnd(WidgetTester tester) async {
  final scrollable = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  if (scrollable.evaluate().isEmpty) return;
  for (var step = 0; step < 20; step++) {
    await tester.drag(scrollable.first, const Offset(0, -300));
    await tester.pump();
  }
}
