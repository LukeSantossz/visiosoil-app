// Acceptance criteria of SPEC 0220: the correction dialog offers the classes
// the model classifies, plus "Não informada", with the record's true class
// selected, and resolves to the choice and the typed sample on "Salvar" and to
// nothing on "Cancelar".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/widgets/correction_dialog.dart';
import 'package:visiosoil_app/models/soil_record.dart';

const _record = SoilRecord(
  id: 1,
  imagePath: 'x.png',
  timestamp: '2026-06-26T12:00:00Z',
  textureClass: 'Argilosa',
  fieldName: 'Talhão 3',
  sampleLabel: 'A1',
  trueTextureClass: 'Media',
);

void main() {
  late ({String? trueTextureClass, String sampleLabel})? result;
  late bool resolved;

  Future<void> open(WidgetTester tester, SoilRecord record) async {
    resolved = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showCorrectionDialog(context, record);
            resolved = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, String label) {
    final tile = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, label),
    );
    final group =
        tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>));
    return tile.value == group.groupValue;
  }

  testWidgets('correction_dialog_offers_the_model_classes', (tester) async {
    await open(tester, _record);

    expect(find.text('Corrigir classificação'), findsOneWidget);
    for (final label in [
      'Arenosa',
      'Média',
      'Argilosa',
      'Muito argilosa',
      'Não informada',
    ]) {
      expect(
        find.widgetWithText(RadioListTile<String>, label),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.byType(RadioListTile<String>), findsNWidgets(5));
    expect(find.widgetWithText(TextField, 'Talhão'), findsNothing);
    expect(find.widgetWithText(TextField, 'Amostra'), findsOneWidget);
    expect(selected(tester, 'Média'), isTrue);
    expect(selected(tester, 'Não informada'), isFalse);
  });

  testWidgets('a record without a true class selects "Não informada"',
      (tester) async {
    await open(tester, const SoilRecord(imagePath: 'x.png', timestamp: 't'));

    expect(selected(tester, 'Não informada'), isTrue);
    expect(selected(tester, 'Média'), isFalse);
  });

  testWidgets('correction_dialog_writes_the_choice', (tester) async {
    await open(tester, _record);

    await tester.tap(find.text('Argilosa'));
    await tester.enterText(find.widgetWithText(TextField, 'Amostra'), '12');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
    expect(result, (trueTextureClass: 'Argilosa', sampleLabel: '12'));
  });

  testWidgets('"Não informada" resolves to no class', (tester) async {
    await open(tester, _record);

    await tester.tap(find.text('Não informada'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(result, (trueTextureClass: null, sampleLabel: 'A1'));
  });

  testWidgets('cancelling resolves to nothing', (tester) async {
    await open(tester, _record);

    await tester.tap(find.text('Argilosa'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
    expect(result, isNull);
  });
}
