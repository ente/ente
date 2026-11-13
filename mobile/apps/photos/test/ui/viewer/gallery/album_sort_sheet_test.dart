import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/viewer/gallery/hooks/album_sort_sheet.dart";

void main() {
  testWidgets("shows the saved order and returns the selected order", (
    tester,
  ) async {
    for (final ascending in [false, true]) {
      bool? selected;
      await _pumpLauncher(
        tester,
        ascending: ascending,
        onSelected: (value) => selected = value,
      );
      await tester.tap(find.text("Sort"));
      await tester.pumpAndSettle();
      final currentOrder = ascending ? "Oldest first" : "Newest first";
      expect(find.text("Sort photos"), findsOneWidget);
      final choices = tester.widgetList<MenuComponent>(
        find.byType(MenuComponent),
      );
      expect(
        choices.singleWhere((choice) => choice.trailing != null).title,
        currentOrder,
      );
      await tester.tap(find.text(ascending ? "Newest first" : "Oldest first"));
      await tester.pumpAndSettle();
      expect(selected, !ascending);
      expect(find.byType(BottomSheetComponent), findsNothing);
    }
  });

  testWidgets("keeps sorting reachable in dark landscape with large text", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(667, 240);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    bool? selected;
    await _pumpLauncher(
      tester,
      dark: true,
      onSelected: (value) => selected = value,
    );
    await tester.tap(find.text("Sort"));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("Oldest first"));
    await tester.tap(find.text("Oldest first"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selected, isTrue);
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  bool ascending = false,
  bool dark = false,
  required ValueChanged<bool> onSelected,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: (dark ? darkThemeData : lightThemeData).copyWith(
        platform: dark ? TargetPlatform.iOS : TargetPlatform.android,
      ),
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final selection = await showAlbumSortSheet(
                context,
                ascending: ascending,
              );
              if (selection != null) onSelected(selection);
            },
            child: Text(context.strings.sort),
          ),
        ),
      ),
    ),
  );
}
