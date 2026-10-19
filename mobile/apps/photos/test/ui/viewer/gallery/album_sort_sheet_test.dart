import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/ui/viewer/gallery/hooks/album_sort_sheet.dart";

void main() {
  testWidgets("shows the saved order and returns the selected order", (
    tester,
  ) async {
    const labels = ["Newest first", "Oldest first", "A-Z", "Z-A"];
    for (final order in FileSortOrder.values) {
      FileSortOrder? selected;
      await _pumpLauncher(
        tester,
        sortOrder: order,
        onSelected: (value) => selected = value,
      );
      await tester.tap(find.text("Sort"));
      await tester.pumpAndSettle();
      final currentOrder = labels[order.index];
      expect(find.text("Sort photos"), findsOneWidget);
      final choices = tester.widgetList<MenuComponent>(
        find.byType(MenuComponent),
      );
      expect(choices.map((choice) => choice.title), labels);
      expect(
        choices.singleWhere((choice) => choice.trailing != null).title,
        currentOrder,
      );
      final next = FileSortOrder.values[(order.index + 1) % labels.length];
      await tester.tap(find.text(labels[next.index]));
      await tester.pumpAndSettle();
      expect(selected, next);
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
    FileSortOrder? selected;
    await _pumpLauncher(
      tester,
      dark: true,
      onSelected: (value) => selected = value,
    );
    await tester.tap(find.text("Sort"));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("Z-A"));
    await tester.tap(find.text("Z-A"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selected, FileSortOrder.filenameDescending);
  });
}

Future<void> _pumpLauncher(
  WidgetTester tester, {
  FileSortOrder sortOrder = FileSortOrder.newestFirst,
  bool dark = false,
  required ValueChanged<FileSortOrder> onSelected,
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
                sortOrder: sortOrder,
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
