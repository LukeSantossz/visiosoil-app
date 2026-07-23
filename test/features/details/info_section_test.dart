// Widget tests for the extracted InfoSection (#120): the location and date
// tiles always render; the texture tile appears only for a classified record.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/models/soil_record.dart';

SoilRecord recordWith({String? textureClass}) => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      address: 'São Paulo, SP',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: textureClass,
      confidenceScore: textureClass == null ? null : 0.9,
    );

Future<void> pumpInfo(WidgetTester tester, SoilRecord record) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: InfoSection(record: record)),
      ),
    ),
  );
}

void main() {
  testWidgets('always renders the location and collection-date tiles',
      (tester) async {
    await pumpInfo(tester, recordWith());

    expect(find.text('Localização'), findsOneWidget);
    expect(find.text('Data da coleta'), findsOneWidget);
  });

  testWidgets('shows the texture tile only for a classified record',
      (tester) async {
    await pumpInfo(tester, recordWith());
    expect(find.text('Classe textural'), findsNothing);

    await pumpInfo(tester, recordWith(textureClass: 'Argilosa'));
    expect(find.text('Classe textural'), findsOneWidget);
  });
}
