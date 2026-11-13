import 'package:ente_auth/ui/home/widgets/home_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('activates search before handing the first key to the IME', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    var visible = false;
    late StateSetter setHarnessState;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHarnessState = setState;
            return Material(
              child: PersistentSearchField(
                visible: visible,
                child: TextField(controller: controller, focusNode: focusNode),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isFalse);

    final handled = activateHomeSearchFromKeyEvent(
      showSearch: () {
        setHarnessState(() {
          visible = true;
        });
      },
      focusNode: focusNode,
    );

    expect(handled, isFalse);
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);

    await tester.pump();
    const composingValue = TextEditingValue(
      text: 'に',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 1),
    );
    tester.testTextInput.updateEditingValue(composingValue);
    await tester.pump();

    expect(controller.value, composingValue);
  });
}
