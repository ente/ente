import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets(
    "TextInputComponent renders label, required mark, and helper message",
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TextInputComponent(
            label: "Email",
            hintText: "name@example.com",
            message: "Use your account email",
            isRequired: true,
          ),
        ),
      );

      expect(_richText("Email *"), findsNothing);
      expect(find.text("Email"), findsOneWidget);
      expect(find.text("*"), findsOneWidget);
      expect(find.text("Use your account email"), findsOneWidget);
      expect(
        tester.widget<Text>(find.text("Use your account email")).style?.color,
        ColorTokens.light.textLight,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        "name@example.com",
      );
    },
  );

  testWidgets("TextInputComponent renders error message visuals", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TextInputComponent(
          label: "Password",
          message: "Password is required",
          messageType: TextInputComponentMessageType.error,
        ),
      ),
    );

    expect(find.text("Password is required"), findsOneWidget);
    expect(
      tester.widget<Text>(find.text("Password is required")).style?.color,
      ColorTokens.light.warning,
    );
    expect(
      _fieldDecoration(tester).border?.top.color,
      ColorTokens.light.warning,
    );
  });

  testWidgets("TextInputComponent renders success message visuals", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TextInputComponent(
          label: "Code",
          message: "Looks good",
          messageType: TextInputComponentMessageType.success,
        ),
      ),
    );

    expect(find.text("Looks good"), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(
      tester.widget<Text>(find.text("Looks good")).style?.color,
      ColorTokens.light.primary,
    );
    expect(
      _fieldDecoration(tester).border?.top.color,
      ColorTokens.light.primary,
    );
  });

  testWidgets("TextInputComponent maps actual focus to the focused border", (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const TextInputComponent(label: "Email")));

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(
      _fieldDecoration(tester).border?.top.color,
      ColorTokens.light.textLighter,
    );
  });

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

  testWidgets("TextInputComponent maps error and success states to borders", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            TextInputComponent(
              label: "Error",
              message: "This is an error",
              messageType: TextInputComponentMessageType.error,
            ),
            TextInputComponent(
              label: "Success",
              message: "Saved",
              messageType: TextInputComponentMessageType.success,
            ),
          ],
        ),
      ),
    );

    final borders = tester
        .widgetList<Container>(_fieldContainers())
        .map((container) => container.decoration! as BoxDecoration)
        .map((decoration) => decoration.border! as Border)
        .toList();

    expect(borders.first.top.color, ColorTokens.light.warning);
    expect(borders.first.top.width, 1);
    expect(borders.last.top.color, ColorTokens.light.primary);
    expect(borders.last.top.width, 1);
  });

  testWidgets(
    "TextInputComponent forwards disabled state to the platform field",
    (tester) async {
      await tester.pumpWidget(
        _wrap(const TextInputComponent(label: "Email", isDisabled: true)),
      );

      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.enabled, isFalse);
      expect(_fieldDecoration(tester).color, ColorTokens.light.fillDark);
      expect(
        _fieldDecoration(tester).border?.top.color,
        ColorTokens.light.strokeFaint,
      );
    },
  );

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

  testWidgets("TextInputComponent supports the multiline layout", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TextInputComponent(
          label: "Notes",
          hintText: "Hint text",
          message: "This is an error",
          messageType: TextInputComponentMessageType.error,
          maxLines: 4,
          suffix: Icon(Icons.copy, key: ValueKey("copy-icon")),
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: _fieldContainers().first,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Padding &&
                  widget.padding ==
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          )
          .first,
    );

    expect(input.maxLines, 4);
    expect(
      padding.padding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
    expect(_fieldDecoration(tester).borderRadius, BorderRadius.circular(16));
    expect(
      _fieldDecoration(tester).border?.top.color,
      ColorTokens.light.warning,
    );
    expect(find.byKey(const ValueKey("copy-icon")), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey("copy-icon"))).dy,
      tester.getTopLeft(find.byType(TextField)).dy,
    );
    expect(
      tester.widget<Text>(find.text("This is an error")).style?.fontSize,
      TextStyles.mini.fontSize,
    );
  });

  testWidgets("TextInputComponent accepts text entry and reports changes", (
    tester,
  ) async {
    final controller = TextEditingController();
    var changedValue = "";
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        TextInputComponent(
          controller: controller,
          label: "Name",
          onChanged: (value) => changedValue = value,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), "Ada Lovelace");
    await tester.pump();

    expect(controller.text, "Ada Lovelace");
    expect(changedValue, "Ada Lovelace");
    expect(find.text("Ada Lovelace"), findsOneWidget);
  });

  testWidgets("TextInputComponent forwards production text input behavior", (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final isEmptyNotifier = ValueNotifier<bool>(false);
    var submitted = "";
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(isEmptyNotifier.dispose);

    await tester.pumpWidget(
      _wrap(
        TextInputComponent(
          controller: controller,
          focusNode: focusNode,
          isEmptyNotifier: isEmptyNotifier,
          label: "Invite email",
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp("[a-z@.]")),
          ],
          maxLength: 48,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          onSubmit: (value) => submitted = value,
        ),
      ),
    );

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.focusNode, focusNode);
    expect(input.autofocus, isTrue);
    expect(input.textCapitalization, TextCapitalization.words);
    expect(input.maxLength, isNull);
    expect(input.keyboardType, TextInputType.emailAddress);
    expect(input.autofillHints, const [AutofillHints.email]);
    expect(input.autocorrect, isFalse);

    await tester.enterText(find.byType(TextField), "mira@example.com");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, "mira@example.com");
    expect(isEmptyNotifier.value, isFalse);
  });

  testWidgets(
    "TextInputComponent supports clear and password visibility affordances",
    (tester) async {
      final clearController = TextEditingController(text: "search");
      final passwordController = TextEditingController(text: "secret");
      addTearDown(clearController.dispose);
      addTearDown(passwordController.dispose);

      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              TextInputComponent(
                controller: clearController,
                label: "Search",
                isClearable: true,
              ),
              TextInputComponent(
                controller: passwordController,
                label: "Password",
                isPasswordInput: true,
              ),
            ],
          ),
        ),
      );

      expect(find.byKey(const ValueKey("text-field-clear")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("text-field-clear")));
      await tester.pump();
      expect(clearController.text, "");
      expect(find.byKey(const ValueKey("text-field-clear")), findsNothing);

      var inputs = tester.widgetList<TextField>(find.byType(TextField));
      expect(inputs.last.obscureText, isTrue);

      await tester.tap(
        find.byKey(const ValueKey("text-field-password-toggle")),
      );
      await tester.pump();
      inputs = tester.widgetList<TextField>(find.byType(TextField));
      expect(inputs.last.obscureText, isFalse);
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

  testWidgets("TextInputComponent renders alert message visuals", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TextInputComponent(
          label: "Recovery key",
          message: "Save this somewhere safe.",
          messageType: TextInputComponentMessageType.alert,
        ),
      ),
    );

    expect(find.text("Save this somewhere safe."), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(
      tester.widget<Text>(find.text("Save this somewhere safe.")).style?.color,
      ColorTokens.light.warning,
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

Finder _richText(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && widget.textSpan?.toPlainText() == value,
  );
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
