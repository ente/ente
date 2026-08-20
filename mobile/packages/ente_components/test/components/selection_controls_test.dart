import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
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
