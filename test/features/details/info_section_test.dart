// Widget tests for the extracted InfoSection (#120): the location and date
// tiles always render; the texture tile appears only for a classified record.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/models/soil_record.dart';

SoilRecord recordWith({String? textureClass}) => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      address: 'São Paulo, SP',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: textureClass,
      confidenceScore: textureClass == null ? null : 0.9,
    );

Future<void> pumpInfo(
  WidgetTester tester,
  SoilRecord record, {
  ThemeData? theme,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme,
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

  // In high contrast the card's edge is solid and 2 dp wide (SPEC 0135).
  testWidgets('hc_edges_are_thicker: the info card', (tester) async {
    await pumpInfo(tester, recordWith(), theme: AppTheme.lightHighContrast);

    final card = tester.widget<Container>(find.descendant(
      of: find.byType(InfoSection),
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).border != null),
    ).first);
    final edge = ((card.decoration! as BoxDecoration).border! as Border).top;
    expect(edge.color, AppPalette.lightHighContrast.outline);
    expect(edge.width, 2);
  });
}
