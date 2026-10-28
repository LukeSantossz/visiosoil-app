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

  // SPEC 0148: the accuracy reads under the coordinates, known or not, and
  // never without them.
  testWidgets('details_show_known_accuracy', (tester) async {
    await pumpInfo(
      tester,
      const SoilRecord(
        imagePath: 'x.png',
        latitude: -23.5,
        longitude: -46.6,
        timestamp: '2026-06-26T12:00:00Z',
        horizontalAccuracy: 4.2,
      ),
    );

    expect(
      find.text('-23.500000, -46.600000\nPrecisão estimada: ± 5 m'),
      findsOneWidget,
    );
  });

  testWidgets('details_show_unavailable_accuracy', (tester) async {
    await pumpInfo(
      tester,
      const SoilRecord(
        imagePath: 'x.png',
        latitude: -23.5,
        longitude: -46.6,
        timestamp: '2026-06-26T12:00:00Z',
      ),
    );
    expect(
      find.text('-23.500000, -46.600000\nPrecisão não disponível'),
      findsOneWidget,
    );

    await pumpInfo(tester, recordWith());
    expect(find.textContaining('Precisão'), findsNothing);
  });

  // SPEC 0149, SPEC 0220: the identification tile names the true class and
  // the sample the record has, never the field, and says when it has none.
  testWidgets('identification_shows_the_true_class', (tester) async {
    await pumpInfo(
      tester,
      recordWith().copyWith(
        fieldName: 'Talhão 3',
        trueTextureClass: 'Argilosa',
        sampleLabel: '12',
      ),
    );
    expect(find.text('Identificação'), findsOneWidget);
    expect(find.text('Classe real: Argilosa\nAmostra: 12'), findsOneWidget);
    expect(find.textContaining('Talhão'), findsNothing);

    await pumpInfo(
      tester,
      recordWith().copyWith(trueTextureClass: 'Muito Argilosa'),
    );
    expect(find.text('Classe real: Muito argilosa'), findsOneWidget);

    await pumpInfo(tester, recordWith().copyWith(sampleLabel: 'A1'));
    expect(find.text('Amostra: A1'), findsOneWidget);
    expect(find.textContaining('Classe real:'), findsNothing);
  });

  testWidgets('a field label alone is no identification', (tester) async {
    await pumpInfo(tester, recordWith().copyWith(fieldName: 'Talhão 3'));

    expect(find.text('Sem identificação'), findsOneWidget);
  });

  testWidgets('details_show_no_identification', (tester) async {
    await pumpInfo(tester, recordWith());

    expect(find.text('Identificação'), findsOneWidget);
    expect(find.text('Sem identificação'), findsOneWidget);
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
