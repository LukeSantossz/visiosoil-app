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
  // Approved copy (redesign v11 §3.14, decision 14.2).
  const lowText =
      'O modelo não está seguro. Refaça a foto na sombra, com a amostra '
      'preenchendo a moldura.';
  const moderateText =
      'Resultado provável. Se puder, refaça a foto para confirmar.';

  testWidgets('shows the low-confidence banner below 50%', (tester) async {
    await pumpHeader(tester, 0.4);

    expect(find.text(lowText), findsOneWidget);
    expect(find.text(moderateText), findsNothing);
  });

  testWidgets('shows the moderate-confidence banner in the 50-74% range',
      (tester) async {
    await pumpHeader(tester, 0.7);

    expect(find.text(moderateText), findsOneWidget);
    expect(find.text(lowText), findsNothing);
  });

  testWidgets('shows no advisory banner at high confidence', (tester) async {
    await pumpHeader(tester, 0.95);

    expect(find.text(lowText), findsNothing);
    expect(find.text(moderateText), findsNothing);
  });

  testWidgets('renders the texture class name and the confidence badge',
      (tester) async {
    await pumpHeader(tester, 0.95);

    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.text('Confiança alta · 95%'), findsOneWidget);
  });
}
