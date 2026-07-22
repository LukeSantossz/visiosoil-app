// Tests for [confirmDestructiveAction]: the shared confirm-then-delete dialog
// the three destructive flows (history, details, settings) delegate to. Driven
// through a host button so the helper can be exercised without a real screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/confirm_destructive_action.dart';

void main() {
  // A distinctive error color so the confirm-button assertion proves the style
  // is read from the theme's colorScheme.error, not hardcoded.
  const errorColor = Color(0xFF123456);

  // Pumps a host with a single button whose tap opens the shared dialog and
  // records the resolved choice into [onResult].
  Future<void> pumpHost(
    WidgetTester tester,
    void Function(bool) onResult,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.from(
          colorScheme: const ColorScheme.light(error: errorColor),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final choice = await confirmDestructiveAction(
                  context,
                  title: 'Excluir?',
                  message: 'Mensagem de confirmação',
                  confirmLabel: 'Confirmar',
                );
                onResult(choice);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('returns true when the confirm button is tapped', (tester) async {
    bool? result;
    await pumpHost(tester, (choice) => result = choice);

    expect(find.text('Excluir?'), findsOneWidget);
    expect(find.text('Mensagem de confirmação'), findsOneWidget);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('returns false when cancel is tapped', (tester) async {
    bool? result;
    await pumpHost(tester, (choice) => result = choice);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('returns false when the barrier is dismissed', (tester) async {
    bool? result;
    await pumpHost(tester, (choice) => result = choice);

    // Tap outside the dialog to dismiss it via the modal barrier.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('styles the confirm button with the theme error color',
      (tester) async {
    await pumpHost(tester, (_) {});

    final confirmButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Confirmar'),
    );
    final foreground =
        confirmButton.style?.foregroundColor?.resolve(<WidgetState>{});

    expect(foreground, errorColor);
  });
}
