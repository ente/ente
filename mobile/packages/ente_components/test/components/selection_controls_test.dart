import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";

void main() {
  testWidgets("CheckboxComponent toggles to the next selected value", (
    tester,
  ) async {
    bool? nextValue;

    await tester.pumpWidget(
      _wrap(
        CheckboxComponent(
          selected: false,
          onChanged: (value) => nextValue = value,
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(nextValue, isTrue);
  });

  testWidgets("RadioComponent toggles to the next selected value", (
    tester,
  ) async {
    bool? nextValue;

    await tester.pumpWidget(
      _wrap(
        RadioComponent(
          selected: false,
          onChanged: (value) => nextValue = value,
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(nextValue, isTrue);
  });

  testWidgets("ToggleSwitchComponent toggles to the next selected value", (
    tester,
  ) async {
    bool? nextValue;

    await tester.pumpWidget(
      _wrap(
        ToggleSwitchComponent(
          selected: false,
          onChanged: (value) => nextValue = value,
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(nextValue, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
  });

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

  testWidgets("ToggleSwitchComponent uses Cupertino switch on iOS", (
    tester,
  ) async {
    bool? nextValue;

    await tester.pumpWidget(
      _wrap(
        ToggleSwitchComponent(
          selected: false,
          onChanged: (value) => nextValue = value,
        ),
        platform: TargetPlatform.iOS,
      ),
    );

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pump();

    expect(nextValue, isTrue);
    expect(find.byType(Switch), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets("LabeledControlComponent renders label and subtitle", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const LabeledControlComponent(
          control: CheckboxComponent(selected: true, onChanged: null),
          label: "Back up automatically",
          subtitle: "Includes new photos",
        ),
      ),
    );

    expect(find.text("Back up automatically"), findsOneWidget);
    expect(find.text("Includes new photos"), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      tester.widget<Text>(find.text("Back up automatically")).style?.fontFamily,
      TextStyles.body.fontFamily,
    );
    expect(
      tester.widget<Text>(find.text("Includes new photos")).style?.fontFamily,
      TextStyles.mini.fontFamily,
    );
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

  testWidgets("FilterChipComponent renders selected state with token colors", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          label: "Faces",
          state: FilterChipComponentState.selected,
        ),
      ),
    );

    final surfaceFinder = find.byKey(const ValueKey("filter-chip-surface"));
    final surface = tester.widget<AnimatedContainer>(surfaceFinder);
    final decoration = surface.decoration! as BoxDecoration;
    final label = tester.widget<Text>(find.text("Faces"));

    expect(tester.getSize(surfaceFinder).height, 40);
    expect(decoration.color, ColorTokens.dark.backgroundBase);
    expect(label.style?.color, ColorTokens.light.textReverse);
    expect(find.byWidgetPredicate(_isCancelIcon), findsOneWidget);
    expect(
      tester.widget<HugeIcon>(find.byWidgetPredicate(_isCancelIcon)).size,
      14,
    );
  });

  testWidgets("FilterChipComponent inverts selected colors in dark theme", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          label: "Faces",
          state: FilterChipComponentState.selected,
        ),
        theme: ComponentTheme.darkTheme(),
      ),
    );

    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey("filter-chip-surface")),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final label = tester.widget<Text>(find.text("Faces"));

    expect(decoration.color, ColorTokens.light.backgroundBase);
    expect(label.style?.color, ColorTokens.dark.textReverse);
    expect(find.byWidgetPredicate(_isCancelIcon), findsOneWidget);
  });

  testWidgets("FilterChipComponent toggles only when enabled", (tester) async {
    bool? nextValue;

    await tester.pumpWidget(
      _wrap(
        FilterChipComponent(
          label: "Albums",
          state: FilterChipComponentState.unselected,
          onChanged: (value) => nextValue = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey("filter-chip-surface")));
    await tester.pump();

    expect(nextValue, isTrue);

    await tester.pumpWidget(
      _wrap(
        FilterChipComponent(
          label: "Albums",
          state: FilterChipComponentState.disabled,
          onChanged: (value) => nextValue = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey("filter-chip-surface")));
    await tester.pump();

    expect(nextValue, isTrue);
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

  testWidgets("FilterChipComponent keeps avatar fixed by default", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          avatar: ColoredBox(key: ValueKey("avatar"), color: Colors.purple),
          state: FilterChipComponentState.unselected,
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey("avatar"))),
      const Size.square(32),
    );
  });

  testWidgets("FilterChipComponent scales avatar when enabled", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          avatar: ColoredBox(key: ValueKey("avatar"), color: Colors.purple),
          state: FilterChipComponentState.unselected,
          scaleAvatarWithText: true,
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey("avatar"))),
      const Size.square(48),
    );
  });

  testWidgets("FilterChipComponent uses custom avatar size", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          avatar: ColoredBox(key: ValueKey("avatar"), color: Colors.purple),
          state: FilterChipComponentState.unselected,
          avatarSize: 48,
        ),
      ),
    );

    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey("filter-chip-surface")),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final avatarClip = tester.widget<ClipRRect>(find.byType(ClipRRect));

    expect(
      tester.getSize(find.byKey(const ValueKey("avatar"))),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey("filter-chip-surface"))).height,
      56,
    );
    expect(decoration.borderRadius, BorderRadius.circular(28));
    expect(avatarClip.borderRadius, BorderRadius.circular(24));
  });

  testWidgets("FilterChipComponent scales custom avatar size when needed", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          avatar: ColoredBox(key: ValueKey("avatar"), color: Colors.purple),
          state: FilterChipComponentState.unselected,
          avatarSize: 40,
          scaleAvatarWithText: true,
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey("avatar"))),
      const Size.square(48),
    );
  });

  testWidgets("FilterChipComponent clips avatar content", (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FilterChipComponent(
          label: "Mira",
          avatar: ColoredBox(color: Colors.purple),
          state: FilterChipComponentState.unselected,
        ),
      ),
    );

    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.text("Mira"), findsOneWidget);
  });
}

Widget _wrap(
  Widget child, {
  TargetPlatform platform = TargetPlatform.android,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: (theme ?? ComponentTheme.lightTheme()).copyWith(platform: platform),
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

bool _isCancelIcon(Widget widget) {
  return widget is HugeIcon && widget.icon == HugeIcons.strokeRoundedCancel01;
}
