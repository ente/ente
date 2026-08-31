import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("TextInputComponent unfocuses when tapping outside", (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            TextInputComponent(label: "Email", focusNode: focusNode),
            const SizedBox(height: 40),
            const Text("Outside"),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text("Outside"));
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  });

  testWidgets(
    "TextInputComponent forwards read-only state while staying enabled",
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TextInputComponent(
            label: "Username",
            initialValue: "hello",
            readOnly: true,
          ),
        ),
      );

      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.readOnly, isTrue);
      expect(input.enabled, isTrue);
      expect(_fieldDecoration(tester).color, ColorTokens.light.fillLight);
    },
  );

  testWidgets(
    "TextInputComponent gives suffix actions a 48px tap target without resizing",
    (tester) async {
      var suffixTapCount = 0;

      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 240,
            child: TextInputComponent(
              suffix: const Icon(
                Icons.close_rounded,
                key: ValueKey("custom-suffix-icon"),
              ),
              onSuffixTap: () => suffixTapCount++,
            ),
          ),
        ),
      );

      final fieldFinder = _fieldContainers().first;
      final fieldRect = tester.getRect(fieldFinder);

      expect(fieldRect.height, 52);

      await tester.tapAt(Offset(fieldRect.right - 51, fieldRect.center.dy));
      await tester.pump();

      expect(suffixTapCount, 1);
      expect(tester.getRect(fieldFinder).height, 52);
    },
  );

  testWidgets("TextInputComponent grows the suffix slot to fit wide suffixes", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 240,
          child: TextInputComponent(
            suffix: SizedBox(
              key: ValueKey("wide-suffix"),
              width: 80,
              height: 48,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey("wide-suffix"))).width, 80);
  });

  testWidgets("TextInputComponent centers single-line affixes vertically", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 240,
          child: TextInputComponent(
            prefix: Icon(Icons.search, key: ValueKey("prefix-icon")),
            suffix: Icon(Icons.close_rounded, key: ValueKey("suffix-icon")),
            onSuffixTap: _noop,
          ),
        ),
      ),
    );

    final fieldCenter = tester.getRect(_fieldContainers().first).center.dy;

    expect(
      tester.getRect(find.byKey(const ValueKey("prefix-icon"))).center.dy,
      fieldCenter,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey("suffix-icon"))).center.dy,
      fieldCenter,
    );
  });

  testWidgets("TextInputComponent submits without surfacing execution UI", (
    tester,
  ) async {
    final submitNotifier = ValueNotifier<int>(0);
    final submitCompleter = Completer<void>();
    var submitCount = 0;
    addTearDown(submitNotifier.dispose);

    await tester.pumpWidget(
      _wrap(
        TextInputComponent(
          initialValue: "album",
          submitNotifier: submitNotifier,
          onSubmit: (_) {
            submitCount += 1;
            return submitCompleter.future;
          },
        ),
      ),
    );

    submitNotifier.value++;
    await tester.pump();
    submitNotifier.value++;
    await tester.pump();

    expect(submitCount, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    submitCompleter.complete();
    await tester.pump();
    submitNotifier.value++;
    await tester.pump();

    expect(submitCount, 2);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  testWidgets("TextInputComponent surfaces wrong password as an error border", (
    tester,
  ) async {
    final submitNotifier = ValueNotifier<int>(0);
    addTearDown(submitNotifier.dispose);

    await tester.pumpWidget(
      _wrap(
        TextInputComponent(
          initialValue: "secret",
          submitNotifier: submitNotifier,
          popNavAfterSubmission: true,
          onSubmit: (_) => throw Exception("Incorrect password"),
        ),
      ),
    );

    submitNotifier.value++;
    await tester.pump();

    expect(
      _fieldDecoration(tester).border?.top.color,
      ColorTokens.light.warning,
    );
  });

  testWidgets("TextInputComponent listens for cancel notifications", (
    tester,
  ) async {
    final cancelNotifier = ValueNotifier<int>(0);
    final controller = TextEditingController(text: "draft");
    addTearDown(cancelNotifier.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        TextInputComponent(
          controller: controller,
          cancelNotifier: cancelNotifier,
        ),
      ),
    );

    cancelNotifier.value++;
    await tester.pump();

    expect(controller.text, "");
  });
}

Finder _fieldContainers() {
  return find.byWidgetPredicate((widget) {
    if (widget is! Container || widget.decoration is! BoxDecoration) {
      return false;
    }
    final decoration = widget.decoration! as BoxDecoration;
    return decoration.borderRadius == BorderRadius.circular(16) &&
        decoration.border is Border;
  });
}

BoxDecoration _fieldDecoration(WidgetTester tester) {
  return tester.widget<Container>(_fieldContainers().first).decoration!
      as BoxDecoration;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ComponentTheme.lightTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );
}

void _noop() {}
