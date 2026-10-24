// SwipeToDelete (redesign v11 §4): closed/revealed/exiting states, with a
// non-gesture "Excluir" custom semantics action fallback (redesign v11 §8).
// No caller yet (PR 10 wires this into the history screen).
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/swipe_to_delete.dart';

import '../../support/haptics_recorder.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget row() => const SizedBox(
      height: 56,
      width: 400,
      child: Center(child: Text('Argilosa')),
    );

void main() {
  testWidgets('closed: shows the child and no delete button', (tester) async {
    await tester.pumpWidget(host(SwipeToDelete(
      onDelete: () {},
      child: row(),
    )));
    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.text('Excluir'), findsNothing);
  });

  testWidgets(
      'revealed: dragging left past the threshold reveals the delete '
      'button and plays the selection haptic',
      (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(host(SwipeToDelete(
      onDelete: () {},
      child: row(),
    )));

    await tester.drag(find.text('Argilosa'), const Offset(-80, 0));
    await tester.pump();

    expect(find.text('Excluir'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
  });

  testWidgets(
      'a drag that does not cross the threshold snaps back closed, '
      'no haptic',
      (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(host(SwipeToDelete(
      onDelete: () {},
      child: row(),
    )));

    await tester.drag(find.text('Argilosa'), const Offset(-20, 0));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(haptics, isEmpty);
  });

  group('exiting', () {
    testWidgets(
        'tapping the revealed delete button collapses the row, plays the '
        'result haptic, and calls onDelete',
        (tester) async {
      final haptics = recordHaptics(tester);
      var deletes = 0;
      await tester.pumpWidget(host(SwipeToDelete(
        onDelete: () => deletes++,
        child: row(),
      )));

      await tester.drag(find.text('Argilosa'), const Offset(-80, 0));
      await tester.pump();
      await tester.tap(find.text('Excluir'));
      await tester.pump();

      expect(deletes, 1);
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));

      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SwipeToDelete)).height, 0);
    });

    testWidgets('shows a snackbar with Desfazer, which calls onUndo',
        (tester) async {
      final haptics = recordHaptics(tester);
      var undone = 0;
      await tester.pumpWidget(host(SwipeToDelete(
        onDelete: () {},
        onUndo: () => undone++,
        child: row(),
      )));

      await tester.drag(find.text('Argilosa'), const Offset(-80, 0));
      await tester.pump();
      await tester.tap(find.text('Excluir'));
      await tester.pump();

      expect(find.text('Análise excluída'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Desfazer'));
      expect(undone, 1);
      expect(haptics, contains('HapticFeedbackType.lightImpact'));
    });

    testWidgets('no Desfazer action when onUndo is not given',
        (tester) async {
      recordHaptics(tester);
      await tester.pumpWidget(host(SwipeToDelete(
        onDelete: () {},
        child: row(),
      )));

      await tester.drag(find.text('Argilosa'), const Offset(-80, 0));
      await tester.pump();
      await tester.tap(find.text('Excluir'));
      await tester.pump();

      expect(find.text('Análise excluída'), findsOneWidget);
      expect(find.text('Desfazer'), findsNothing);
    });
  });

  testWidgets(
      'the "Excluir" custom semantics action deletes without a drag gesture',
      (tester) async {
    final semantics = tester.ensureSemantics();
    recordHaptics(tester);
    var deletes = 0;
    await tester.pumpWidget(host(SwipeToDelete(
      onDelete: () => deletes++,
      child: row(),
    )));

    final node = tester.getSemantics(find.byType(SwipeToDelete));
    final actionId = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Excluir'),
    );
    expect(node.getSemanticsData().customSemanticsActionIds, contains(actionId));

    tester.binding.renderViews.single.owner!.semanticsOwner!
        .performAction(node.id, SemanticsAction.customAction, actionId);
    await tester.pump();

    expect(deletes, 1);
    semantics.dispose();
  });

  testWidgets('threshold is configurable', (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(host(SwipeToDelete(
      onDelete: () {},
      threshold: 10,
      child: row(),
    )));

    await tester.drag(find.text('Argilosa'), const Offset(-15, 0));
    await tester.pump();

    expect(find.text('Excluir'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.selectionClick'));
  });

  testWidgets(
      "a child's own State survives a swipe (stable widget hierarchy "
      'across drag start/end, not a Transform/AnimatedContainer swap)',
      (tester) async {
    await tester.pumpWidget(host(SwipeToDelete(
      onDelete: () {},
      child: const _CounterProbe(),
    )));

    await tester.tap(find.text('0'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(_CounterProbe)),
    );
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}

/// A stateful probe whose counter would reset to 0 if its ancestor swapped
/// it into a freshly created widget subtree instead of keeping it alive.
class _CounterProbe extends StatefulWidget {
  const _CounterProbe();

  @override
  State<_CounterProbe> createState() => _CounterProbeState();
}

class _CounterProbeState extends State<_CounterProbe> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _count++),
      child: Text('$_count'),
    );
  }
}
