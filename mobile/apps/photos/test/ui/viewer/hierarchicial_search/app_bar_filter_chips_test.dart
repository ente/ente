import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/viewer/hierarchicial_search/app_bar_filter_chips.dart";

void main() {
  testWidgets("AppBarFilterChips keeps default heights without text scaling", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap((context) {
        expect(AppBarFilterChips.chipHeight(context), 40);
        expect(AppBarFilterChips.preferredHeight(context), 48);
        expect(AppBarFilterChips.appBarHeight(context), kToolbarHeight + 48);
        return const SizedBox.shrink();
      }),
    );
  });

  testWidgets("AppBarFilterChips expands heights with scaled text", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap((context) {
        expect(AppBarFilterChips.chipHeight(context), 56);
        expect(AppBarFilterChips.preferredHeight(context), 64);
        expect(AppBarFilterChips.appBarHeight(context), kToolbarHeight + 64);
        return const SizedBox.shrink();
      }, textScaler: const TextScaler.linear(2)),
    );
  });
}

Widget _wrap(
  WidgetBuilder builder, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Builder(builder: builder),
    ),
  );
}
