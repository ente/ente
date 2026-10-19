import "dart:ui" show SemanticsAction, SemanticsActionEvent;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/gestures.dart" show PointerScrollEvent;
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/viewer/gallery/hooks/album_actions_sheet.dart";

void main() {
  group("showAlbumActionsSheet", () {
    testWidgets("keeps the destructive tile last and returns its value", (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? result;
      await _pumpLauncher(tester, (value) => result = value);
      final albumScroll = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      await _openLauncher(tester);
      final tilePositions = [
        "Edit",
        "Pin",
        "Archive",
        "Delete",
      ].map((label) => tester.getTopLeft(find.text(label))).toList();
      expect(
        tilePositions.map((position) => position.dx),
        orderedEquals(
          [...tilePositions.map((position) => position.dx)]..sort(),
        ),
      );
      expect(
        tilePositions.every(
          (position) => position.dy < tester.getTopLeft(find.text("Hide")).dy,
        ),
        isTrue,
      );
      await tester.tap(find.text("Delete"));
      await tester.pumpAndSettle();

      expect(result, "delete");
      expect(find.byType(BottomSheetComponent), findsNothing);
      result = "pending";
      await _openLauncher(tester);
      await tester.longPressAt(const Offset(200, 150));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
      result = "pending";
      await _openLauncher(tester);
      final drag = await tester.startGesture(const Offset(200, 150));
      await drag.moveBy(const Offset(0, -24));
      await drag.moveBy(const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(BottomSheetComponent)).dy,
        greaterThanOrEqualTo(667),
      );
      final offset = albumScroll.pixels;
      expect(offset, greaterThan(0));
      await drag.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(albumScroll.pixels, greaterThan(offset));
      await drag.up();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(BottomSheetComponent), findsNothing);
    });

    testWidgets(
      "keeps landscape actions aligned and reachable on short screens",
      (tester) async {
        tester.view.physicalSize = const Size(667, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        String? result;
        await _pumpLauncher(
          tester,
          (value) => result = value,
          platform: TargetPlatform.iOS,
        );
        final albumScroll = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        await _openLauncher(tester);
        final firstRow = [
          "Edit",
          "Pin",
          "Archive",
          "Delete",
        ].map((label) => tester.getTopLeft(find.text(label)).dy);
        expect(
          firstRow.every((top) => (top - firstRow.first).abs() < 1),
          isTrue,
        );
        expect(
          tester.getTopLeft(find.text("Hide")).dy,
          greaterThan(firstRow.first),
        );
        final sheet = tester.getRect(find.byType(BottomSheetComponent));
        expect(sheet.left, greaterThanOrEqualTo(Spacing.lg));
        expect(sheet.right, lessThanOrEqualTo(667 - Spacing.lg));
        expect(sheet.bottom, 240);
        await tester.ensureVisible(find.text("Cast"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Cast"));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(result, "cast");
        expect(find.byType(BottomSheetComponent), findsNothing);
        result = "pending";
        await _openLauncher(tester);
        await tester.tapAt(Offset(sheet.left / 2, sheet.center.dy));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byType(BottomSheetComponent), findsNothing);
        final semantics = tester.ensureSemantics();
        result = "pending";
        await _openLauncher(tester);
        final barrierLabel = MaterialLocalizations.of(
          tester.element(find.byType(BottomSheetComponent)),
        ).scrimLabel;
        tester.binding.platformDispatcher.onSemanticsActionEvent!(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            nodeId: tester.getSemantics(find.bySemanticsLabel(barrierLabel)).id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byType(BottomSheetComponent), findsNothing);
        semantics.dispose();
        result = "pending";
        await _openLauncher(tester);
        final cancelledDrag = await tester.startGesture(
          Offset(sheet.left / 2, sheet.center.dy),
        );
        await cancelledDrag.moveBy(const Offset(0, -24));
        await tester.pump();
        await cancelledDrag.cancel();
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.byType(BottomSheetComponent), findsNothing);
        result = "pending";
        await _openLauncher(tester);
        final interruptedDrag = await tester.startGesture(
          Offset(sheet.left / 2, sheet.center.dy),
        );
        await interruptedDrag.moveBy(const Offset(0, -24));
        await tester.pump();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text("Next page")),
          ),
        );
        await tester.pumpAndSettle();
        expect(result, isNull);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheetComponent), findsNothing);
        await interruptedDrag.up();
        result = "pending";
        await _openLauncher(tester);
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: Offset(sheet.left / 2, sheet.center.dy),
            scrollDelta: const Offset(0, 60),
          ),
        );
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(albumScroll.pixels, greaterThan(0));
        expect(find.byType(BottomSheetComponent), findsNothing);
        albumScroll.jumpTo(0);
        tester.view.physicalSize = const Size(740, 280);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await _openLauncher(tester);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final (size, width) in [
          (const Size(1024, 1366), 640.0),
          (const Size(1366, 1024), 640.0),
          (const Size(320, 1024), 320.0),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final resizedSheet = tester.getRect(
            find.byType(BottomSheetComponent),
          );
          expect(resizedSheet.width, width);
          expect(resizedSheet.bottom, size.height);
          expect(tester.takeException(), isNull);
        }
        await tester.ensureVisible(find.text("Add photos"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Add photos"));
        await tester.pumpAndSettle();
        expect(result, "add photos");
      },
    );
  });
}

List<EntePopupMenuOption<String>> _options(BuildContext context) {
  EntePopupMenuOption<String> option(String label, {Color? labelColor}) {
    return EntePopupMenuOption(
      value: label.toLowerCase(),
      label: label,
      labelColor: labelColor,
      leadingWidget: const Icon(Icons.circle),
    );
  }

  return [
    option("Edit"),
    option("Pin"),
    option("Archive"),
    option("Hide"),
    option("Cast"),
    option("Download"),
    option("Guest view"),
    option("Add photos"),
    option("Delete", labelColor: context.componentColors.warning),
  ];
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  ValueChanged<String?> onResult, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData.copyWith(platform: platform),
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return ListView(
              children: [
                TextButton(
                  onPressed: () async {
                    onResult(
                      await showAlbumActionsSheet(context, _options(context)),
                    );
                  },
                  child: const Text("Open sheet"),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => fail("A covered album action ran"),
                  onLongPress: () => fail("A covered album action ran"),
                  child: const SizedBox(height: 2000),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _openLauncher(WidgetTester tester) async {
  await tester.tap(find.text("Open sheet"));
  await tester.pumpAndSettle();
}
