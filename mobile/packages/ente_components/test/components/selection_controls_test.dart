import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("CheckboxComponent exposes state and accessible activation", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = false;
    final changes = <bool>[];

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => CheckboxComponent(
            selected: selected,
            onChanged: (value) {
              changes.add(value);
              setState(() => selected = value);
            },
          ),
        ),
      ),
    );

    final checkbox = find.byType(CheckboxComponent);
    for (final expectedSelected in [false, true, false]) {
      final node = tester.getSemantics(checkbox);
      expect(
        node,
        matchesSemantics(
          hasCheckedState: true,
          isChecked: expectedSelected,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      if (changes.length < 2) {
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            nodeId: node.id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pumpAndSettle();
      }
    }
    expect(changes, [true, false]);
    semantics.dispose();
  });

  for (final selected in [false, true]) {
    testWidgets(
      "CheckboxComponent exposes disabled ${selected ? 'checked' : 'unchecked'} state",
      (tester) async {
        final semantics = tester.ensureSemantics();
        var changeCount = 0;

        await tester.pumpWidget(
          _wrap(
            CheckboxComponent(
              selected: selected,
              onChanged: (_) => changeCount++,
            ),
          ),
        );
        await tester.pumpWidget(
          _wrap(CheckboxComponent(selected: selected, onChanged: null)),
        );
        await tester.pumpAndSettle();

        final checkbox = find.byType(CheckboxComponent);
        final node = tester.getSemantics(checkbox);
        expect(
          node,
          matchesSemantics(
            hasCheckedState: true,
            isChecked: selected,
            hasEnabledState: true,
          ),
        );
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            nodeId: node.id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        expect(changeCount, 0);
        semantics.dispose();
      },
    );
  }

  testWidgets("ToggleSwitchComponent shows async loading and success", (
    tester,
  ) async {
    var selected = false;
    final completer = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return ToggleSwitchComponent.async(
              value: () => selected,
              onChanged: () async {
                await completer.future;
                setState(() => selected = !selected);
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.byKey(const ValueKey('toggle-state-loading')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('toggle-state-loading')), findsOneWidget);

    completer.complete();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('toggle-state-success')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('toggle-state-idle')), findsOneWidget);
  });

  testWidgets("ToggleSwitchComponent blocks repeat taps while updating", (
    tester,
  ) async {
    var selected = false;
    var changeCount = 0;
    final completer = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return ToggleSwitchComponent.async(
              value: () => selected,
              onChanged: () async {
                changeCount += 1;
                await completer.future;
                setState(() => selected = !selected);
              },
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(changeCount, 1);

    completer.complete();
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets("ToggleSwitchComponent rolls back when value is not confirmed", (
    tester,
  ) async {
    const selected = false;

    await tester.pumpWidget(
      _wrap(
        ToggleSwitchComponent.async(
          value: () => selected,
          onChanged: () async {},
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets("ToggleSwitchComponent rolls back after async errors", (
    tester,
  ) async {
    const selected = false;
    final completer = Completer<void>();

    await tester.pumpWidget(
      _wrap(
        ToggleSwitchComponent.async(
          value: () => selected,
          loadingDelay: const Duration(milliseconds: 1),
          onChanged: () => completer.future,
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('toggle-state-loading')), findsOneWidget);

    completer.completeError(StateError('failed'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.byKey(const ValueKey('toggle-state-idle')), findsOneWidget);
  });

  testWidgets("LabeledControlComponent wraps long labels", (tester) async {
    const label =
        "This is a deliberately long label that should wrap inside the control row";
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 220,
          child: LabeledControlComponent(
            control: CheckboxComponent(selected: true, onChanged: null),
            label: label,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(label), findsOneWidget);
  });

  testWidgets("FilterChipComponent grows with scaled text", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          label: "Screenshots",
          state: FilterChipComponentState.unselected,
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey("filter-chip-surface"))).height,
      greaterThan(40),
    );
  });

  testWidgets("FilterChipComponent truncates long labels inside a wrap", (
    tester,
  ) async {
    const label =
        "Summer vacation with family and friends in the mountains and by the sea";
    var tapCount = 0;

    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 280,
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8, end: 8),
                  child: FilterChipComponent(
                    label: label,
                    onChanged: (_) => tapCount++,
                  ),
                ),
                const FilterChipComponent(label: "Favorites"),
              ],
            ),
          ),
          textScaler: TextScaler.linear(scale),
        ),
      );

      expect(tester.takeException(), isNull);
      final labelRect = tester.getRect(find.text(label));
      final surfaceRect = tester.getRect(
        find.byKey(const ValueKey("filter-chip-surface")).first,
      );
      expect(labelRect.right, lessThan(surfaceRect.right));
      expect(surfaceRect.width, lessThanOrEqualTo(272));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isTrue,
      );
      await tester.tap(find.text(label));
      await tester.pump();
    }

    expect(tapCount, 2);
  });

  testWidgets("FilterChipComponent keeps short labels compact in a row", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilterChipComponent(label: "Trips", onChanged: (_) {}),
            const Text("More"),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey("filter-chip-surface"))).width,
      lessThan(100),
    );
  });
}

Widget _wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    theme: ComponentTheme.lightTheme().copyWith(
      platform: TargetPlatform.android,
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}
