import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("TagChipComponent renders selected colors", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TagChipComponent(
          label: "Faces",
          leading: Icon(Icons.sell_outlined),
          state: TagChipComponentState.selected,
        ),
      ),
    );

    _expectChipColors(
      tester,
      background: ColorTokens.light.primary,
      content: ColorTokens.light.specialWhite,
    );
  });

  testWidgets("TagChipComponent renders unselected colors", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TagChipComponent(
          label: "Faces",
          leading: Icon(Icons.sell_outlined),
        ),
      ),
    );

    _expectChipColors(
      tester,
      background: ColorTokens.light.fillLight,
      content: ColorTokens.light.textLight,
    );
  });

  testWidgets("TagChipComponent renders disabled colors", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TagChipComponent(
          label: "Faces",
          leading: Icon(Icons.sell_outlined),
          state: TagChipComponentState.disabled,
        ),
      ),
    );

    _expectChipColors(
      tester,
      background: ColorTokens.light.fillLight,
      content: ColorTokens.light.textLightest,
    );
  });

  testWidgets("TagChipComponent invokes tap callback when enabled", (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      _wrap(TagChipComponent(label: "Albums", onTap: () => taps++)),
    );

    await tester.tap(find.byKey(const ValueKey("tag-chip-surface")));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets("TagChipComponent does not invoke tap callback when disabled", (
    tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      _wrap(
        TagChipComponent(
          label: "Albums",
          state: TagChipComponentState.disabled,
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey("tag-chip-surface")));
    await tester.pump();

    expect(taps, 0);
  });

  test("TagChipComponent allows only one icon slot", () {
    expect(
      () => TagChipComponent(
        label: "People",
        leading: const Icon(Icons.person_outline),
        trailing: const Icon(Icons.close_rounded),
      ),
      throwsAssertionError,
    );
  });
}

void _expectChipColors(
  WidgetTester tester, {
  required Color background,
  required Color content,
}) {
  final surfaceFinder = find.byKey(const ValueKey("tag-chip-surface"));
  final surface = tester.widget<AnimatedContainer>(surfaceFinder);
  final decoration = surface.decoration! as BoxDecoration;
  final label = tester.widget<Text>(find.text("Faces"));
  final iconTheme = IconTheme.of(
    tester.element(find.byIcon(Icons.sell_outlined)),
  );

  expect(tester.getSize(surfaceFinder).height, 44);
  expect(decoration.color, background);
  expect(label.style?.color, content);
  expect(iconTheme.color, content);
  expect(find.byIcon(Icons.close_rounded), findsNothing);
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ComponentTheme.lightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}
