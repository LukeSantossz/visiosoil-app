import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

/// Records the primitives `paintVisioSoilMark` draws, so the shared routine's
/// geometry can be asserted without a rasterizer (kept out of CI per spec 0025).
class _RecordingCanvas implements Canvas {
  final List<(Offset, double)> circles = <(Offset, double)>[];
  Offset? lineStart;
  Offset? lineEnd;

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((c, radius));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lineStart = p1;
    lineEnd = p2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets('renders with the VisioSoil semantics label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: VisioSoilLogo(size: 48, color: Colors.white),
          ),
        ),
      ),
    );

    expect(find.byType(VisioSoilLogo), findsOneWidget);
    expect(find.bySemanticsLabel('VisioSoil'), findsOneWidget);
  });

  testWidgets('paints at its declared size even under tight constraints',
      (tester) async {
    // The call sites place the logo in a fixed-size Container (tight
    // constraints); the mark must still render at `size`, not stretch to fill.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: VisioSoilLogo(size: 24, color: Colors.white),
          ),
        ),
      ),
    );

    final paintSize = tester.getSize(
      find.descendant(
        of: find.byType(VisioSoilLogo),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paintSize, const Size(24, 24));
  });

  test('paintVisioSoilMark draws the design-system mark geometry', () {
    // The shared routine feeds both the widget and the launcher-icon generator;
    // asserting its primitives directly gives shared_paint_reused executable
    // coverage in CI (the generator that also uses it is CI-skipped). At a
    // 48-unit size the scale is 1, so coordinates equal the viewBox values.
    final canvas = _RecordingCanvas();
    paintVisioSoilMark(canvas, const Size(48, 48), const Color(0xFFFFFFFF));

    // Lens ring plus three decreasing soil grains.
    expect(canvas.circles, <(Offset, double)>[
      (const Offset(20, 20), 13),
      (const Offset(16.5, 18), 3),
      (const Offset(23.5, 19.5), 2.1),
      (const Offset(19.5, 24.5), 1.4),
    ]);
    // Handle.
    expect(canvas.lineStart, const Offset(29.5, 29.5));
    expect(canvas.lineEnd, const Offset(39, 39));
  });
}
