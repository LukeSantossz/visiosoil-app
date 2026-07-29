import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

typedef _CircleDraw = ({
  Offset center,
  double radius,
  PaintingStyle style,
  double strokeWidth,
  StrokeCap cap,
  Color color,
});

/// Records the primitives `paintVisioSoilMark` draws — including a snapshot of
/// each `Paint` (styles are mutated in place, so values must be captured at draw
/// time) — so the shared routine's geometry AND styling can be asserted without
/// a rasterizer (kept out of CI per spec 0025).
class _RecordingCanvas implements Canvas {
  final List<_CircleDraw> circles = <_CircleDraw>[];
  Offset? lineStart;
  Offset? lineEnd;
  double? lineStrokeWidth;
  StrokeCap? lineCap;
  Color? lineColor;

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add((
        center: c,
        radius: radius,
        style: paint.style,
        strokeWidth: paint.strokeWidth,
        cap: paint.strokeCap,
        color: paint.color,
      ));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lineStart = p1;
    lineEnd = p2;
    lineStrokeWidth = paint.strokeWidth;
    lineCap = paint.strokeCap;
    lineColor = paint.color;
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

  test('paintVisioSoilMark draws the design-system mark geometry and styling',
      () {
    // The shared routine feeds both the widget and the launcher-icon generator;
    // asserting its primitives directly gives shared_paint_reused executable
    // coverage in CI (the generator that also uses it is CI-skipped). At a
    // 48-unit size the scale is 1, so coordinates equal the viewBox values.
    const white = Color(0xFFFFFFFF);
    final canvas = _RecordingCanvas();
    paintVisioSoilMark(canvas, const Size(48, 48), white);

    expect(canvas.circles.length, 4);

    // Lens ring: a round-capped stroke of width 3.2.
    final ring = canvas.circles[0];
    expect(ring.center, const Offset(20, 20));
    expect(ring.radius, 13);
    expect(ring.style, PaintingStyle.stroke);
    expect(ring.strokeWidth, closeTo(3.2, 1e-4));
    expect(ring.cap, StrokeCap.round);
    expect(ring.color, white);

    // Three decreasing soil grains: filled, white.
    final grains = canvas.circles.sublist(1);
    expect(grains.map((g) => g.center), <Offset>[
      const Offset(16.5, 18),
      const Offset(23.5, 19.5),
      const Offset(19.5, 24.5),
    ]);
    expect(grains.map((g) => g.radius), [3, closeTo(2.1, 1e-9), closeTo(1.4, 1e-9)]);
    for (final g in grains) {
      expect(g.style, PaintingStyle.fill);
      expect(g.color, white);
    }

    // Handle: a round-capped stroke of width 3.4.
    expect(canvas.lineStart, const Offset(29.5, 29.5));
    expect(canvas.lineEnd, const Offset(39, 39));
    expect(canvas.lineStrokeWidth, closeTo(3.4, 1e-4));
    expect(canvas.lineCap, StrokeCap.round);
    expect(canvas.lineColor, white);
  });

  test('paintVisioSoilMark scales geometry and stroke widths with size', () {
    // At 96 units the scale is 2, so every coordinate, radius and stroke width
    // doubles — the scaling contract both consumers rely on.
    final canvas = _RecordingCanvas();
    paintVisioSoilMark(canvas, const Size(96, 96), const Color(0xFFFFFFFF));

    final ring = canvas.circles[0];
    expect(ring.center, const Offset(40, 40));
    expect(ring.radius, closeTo(26, 1e-9));
    expect(ring.strokeWidth, closeTo(6.4, 1e-4));
    expect(canvas.lineStart, const Offset(59, 59));
    expect(canvas.lineEnd, const Offset(78, 78));
    expect(canvas.lineStrokeWidth, closeTo(6.8, 1e-4));
  });
}
