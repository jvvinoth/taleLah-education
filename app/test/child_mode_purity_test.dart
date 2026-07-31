/// F7 — No-text-input purity assertion (AC-03).
/// Walks the whole child-mode tree (story scenes → mission wait → handoff →
/// goodbye) and asserts: zero text inputs / keyboards, no settings entry
/// points, system back shows confirm dialog, and Mina's state machine stays
/// a closed set of exactly 8 states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:talelah/providers/app_state.dart';
import 'package:talelah/screens/child_session.dart';
import 'package:talelah/services/api_client.dart';
import 'package:talelah/widgets/mina.dart';

/// The purity walk: nothing in the child tree may summon a keyboard,
/// open settings, or leave the app.
void expectChildModePurity(WidgetTester tester) {
  expect(find.byType(TextField), findsNothing);
  expect(find.byType(TextFormField), findsNothing);
  expect(find.byType(EditableText), findsNothing); // covers every text input
  expect(find.byIcon(Icons.settings), findsNothing);
  expect(find.byIcon(Icons.settings_outlined), findsNothing);
}

Widget childMode() => ChangeNotifierProvider(
      // Unroutable port + no approved story → session stays offline; the
      // demo degradation path renders, which is the same widget tree.
      create: (_) => AppState(api: ApiClient(baseUrl: 'http://127.0.0.1:9')),
      child: const MaterialApp(home: ChildSessionScreen()),
    );

void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532); // 390×844 logical
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  test('Mina has exactly 8 states — the closed set from the spec', () {
    expect(MinaState.values.length, 8);
    expect(
      MinaState.values.map((s) => s.name).toList(),
      [
        'idle',
        'listening',
        'encouraging',
        'celebrating',
        'thinking',
        'demonstrating',
        'waiting',
        'goodbye',
      ],
    );
  });

  testWidgets('child mode is pure end-to-end and blocks system back',
      (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(childMode());
    await tester.pumpAndSettle();

    // Scene 1 · speak — staged reveal: the story card is the only hero,
    // one "My turn!" door into the interaction. No inputs anywhere.
    expectChildModePurity(tester);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('My turn!'), findsOneWidget);

    // "My turn!" reveals the interaction stage — still pure.
    await tester.ensureVisible(find.text('My turn!'));
    await tester.tap(find.text('My turn!'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to read again'), findsOneWidget);
    expectChildModePurity(tester);

    // The recap strip folds the story back open.
    await tester.tap(find.text('Tap to read again'));
    await tester.pumpAndSettle();
    expect(find.text('My turn!'), findsOneWidget);
    expectChildModePurity(tester);

    // System back shows confirm dialog, dismissing it stays on screen.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Leave the story?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(ChildSessionScreen), findsOneWidget);

    // Scene 2 · choice — story stage first, then the adventure deck.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expectChildModePurity(tester);
    await tester.ensureVisible(find.text('My turn!'));
    await tester.tap(find.text('My turn!'));
    await tester.pumpAndSettle();
    expect(find.text('Pick this!'), findsOneWidget);
    expectChildModePurity(tester);

    // Scene 3 · speak.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expectChildModePurity(tester);

    // Scene 4 · mission → the dimmed wait screen (F8).
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expectChildModePurity(tester);
    await tester.ensureVisible(find.text('Start the Mission'));
    await tester.tap(find.text('Start the Mission'));
    await tester.pumpAndSettle();
    expect(find.text("I'm back!"), findsOneWidget);
    expectChildModePurity(tester);

    // Mission wait blocks system back too.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text("I'm back!"), findsOneWidget);

    await tester.tap(find.text("I'm back!"));
    await tester.pumpAndSettle();
    expect(find.text('Mission done — well done!'), findsOneWidget);

    // Scene 5 · family handoff (F9).
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expectChildModePurity(tester);
    await tester.ensureVisible(find.text('We did it! 🙌'));
    await tester.tap(find.text('We did it! 🙌'));
    await tester.pumpAndSettle();

    // Goodbye screen (F10) — consent checkbox defaults to OFF, and the
    // save button without the tick keeps everything unsaved.
    expect(find.text('Great job today!'), findsOneWidget);
    expectChildModePurity(tester);
    final consent = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(consent.value, false);
    await tester.ensureVisible(find.text('Save memory'));
    await tester.tap(find.text('Save memory'));
    await tester.pumpAndSettle();
    expect(find.text('Memory saved for your family'), findsNothing);

    // Goodbye screen still blocks system back.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Great job today!'), findsOneWidget);
  });

  testWidgets('back button tap shows confirm dialog — Stay dismisses it',
      (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(childMode());
    await tester.pumpAndSettle();

    final back = find.byIcon(Icons.arrow_back_rounded);

    // Back button is child-sized (≥44 dp).
    final backSize = tester.getSize(
      find.ancestor(of: back, matching: find.byType(GestureDetector)).first,
    );
    expect(backSize.width, greaterThanOrEqualTo(44));
    expect(backSize.height, greaterThanOrEqualTo(44));

    // Tapping the back button opens a confirm dialog.
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Leave the story?'), findsOneWidget);
    expect(find.text('You can come back and finish later'), findsOneWidget);
    expect(find.text('Stay'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);

    // "Stay" returns to the scene — still pure.
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.byType(ChildSessionScreen), findsOneWidget);
    expectChildModePurity(tester);
  });
}
