import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

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
}
