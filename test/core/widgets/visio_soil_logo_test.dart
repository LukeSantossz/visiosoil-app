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
}
