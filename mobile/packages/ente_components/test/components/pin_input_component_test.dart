import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final allowNonNumeric in [false, true]) {
    testWidgets('PIN input accepts nonnumeric characters: $allowNonNumeric', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? completed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinInputComponent(
              controller: controller,
              length: 4,
              allowNonNumeric: allowNonNumeric,
              onCompleted: (value) => completed = value,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '1a!2');
      await tester.pump();
      expect(controller.text, allowNonNumeric ? '1a!2' : '12');
      expect(completed, allowNonNumeric ? '1a!2' : null);

      controller.text = '3b@4';
      await tester.pump();
      expect(controller.text, allowNonNumeric ? '3b@4' : '34');
      expect(completed, allowNonNumeric ? '3b@4' : null);

      if (allowNonNumeric) {
        controller.clear();
        await tester.enterText(find.byType(TextField), 'a😀!');
        await tester.pump();
        expect(completed, 'a😀!');
        controller.text = 'abc😀';
        await tester.pump();
        expect(controller.text, 'abc');
        controller.text = 'ab🇺🇸';
        await tester.pump();
        expect(controller.text, 'ab');
      }
    });
  }
}
