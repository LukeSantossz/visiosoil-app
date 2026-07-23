// Widget tests for the extracted ClassificationHeader (#120), covering the
// deduplicated confidence banner: low and moderate render their own advisory
// text, high renders none.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/widgets/classification_header.dart';
import 'package:visiosoil_app/models/soil_record.dart';

SoilRecord record(double score) => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: score,
    );

Future<void> pumpHeader(WidgetTester tester, double score) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClassificationHeader(record: record(score)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the low-confidence banner below 60%', (tester) async {
    await pumpHeader(tester, 0.4);

    expect(find.textContaining('Confianca baixa'), findsOneWidget);
    expect(find.textContaining('Confianca moderada'), findsNothing);
  });

  testWidgets('shows the moderate-confidence banner in the 60-79% range',
      (tester) async {
    await pumpHeader(tester, 0.7);

    expect(find.textContaining('Confianca moderada'), findsOneWidget);
    expect(find.textContaining('Confianca baixa'), findsNothing);
  });

  testWidgets('shows no advisory banner at high confidence', (tester) async {
    await pumpHeader(tester, 0.95);

    expect(find.textContaining('Confianca baixa'), findsNothing);
    expect(find.textContaining('Confianca moderada'), findsNothing);
  });

  testWidgets('renders the texture class name and the confidence badge',
      (tester) async {
    await pumpHeader(tester, 0.95);

    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.textContaining('· Alta'), findsOneWidget);
  });
}
