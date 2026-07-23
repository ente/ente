import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter/material.dart" as material show IconButton, Slider;
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("SliderComponent clamps its rendered value", (tester) async {
    await tester.pumpWidget(
      _wrap(SliderComponent(value: 12, min: 0, max: 10, onChanged: (_) {})),
    );

    expect(
      tester.widget<material.Slider>(find.byType(material.Slider)).value,
      10,
    );
  });

  testWidgets("SliderComponent reports value changes from user interaction", (
    tester,
  ) async {
    var value = 0.25;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) {
            return SliderComponent(
              value: value,
              min: 0,
              max: 1,
              onChanged: (nextValue) {
                setState(() => value = nextValue);
              },
            );
          },
        ),
      ),
    );

    await tester.drag(find.byType(material.Slider), const Offset(300, 0));
    await tester.pump();

    expect(value, greaterThan(0.25));
    expect(
      tester.widget<material.Slider>(find.byType(material.Slider)).value,
      value,
    );
  });

  testWidgets("StepperComponent increments and decrements around its value", (
    tester,
  ) async {
    final changedValues = <int>[];

    await tester.pumpWidget(
      _wrap(StepperComponent(value: 5, onChanged: changedValues.add)),
    );

    expect(find.text("5"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();

    expect(changedValues, [6, 4]);
  });

  testWidgets("StepperComponent disables controls at min and max", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(StepperComponent(value: 0, min: 0, max: 1, onChanged: (_) {})),
    );

    final minButtons = tester.widgetList<material.IconButton>(
      find.byType(material.IconButton),
    );
    expect(minButtons.first.onPressed, isNull);
    expect(minButtons.last.onPressed, isNotNull);

    await tester.pumpWidget(
      _wrap(StepperComponent(value: 1, min: 0, max: 1, onChanged: (_) {})),
    );

    final maxButtons = tester.widgetList<material.IconButton>(
      find.byType(material.IconButton),
    );
    expect(maxButtons.first.onPressed, isNotNull);
    expect(maxButtons.last.onPressed, isNull);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ComponentTheme.lightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}
