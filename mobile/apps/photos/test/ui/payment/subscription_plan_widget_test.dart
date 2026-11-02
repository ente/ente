import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/payment/subscription_common_widgets.dart";
import "package:photos/ui/payment/subscription_locker_sheet.dart";
import "package:photos/ui/payment/subscription_page_scaffold.dart";
import "package:photos/ui/payment/subscription_plan_widget.dart";

void main() {
  testWidgets("subscription selection preserves taps and readable Continue", (
    tester,
  ) async {
    final font = FontLoader("packages/ente_components/Outfit")
      ..addFont(
        rootBundle.load("packages/ente_components/fonts/Outfit-Bold.ttf"),
      );
    await font.load();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var selected = false;
    var selections = 0;
    var continues = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: SubscriptionPageScaffold(
          onHelpTap: () {},
          body: StatefulBuilder(
            builder: (context, setState) => GestureDetector(
              onTap: () => setState(() {
                selections++;
                selected = true;
              }),
              child: SubscriptionPlanWidget(
                storage: 10 * 1073741824,
                price: "",
                period: "month",
                isActive: selected,
              ),
            ),
          ),
          actions: [
            SubscriptionContinueButton(
              label: "Continue with 10 GB plan",
              onTap: () => continues++,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Continue with 10 GB plan"), findsOneWidget);

    await _tapAllowanceText(tester, "Locker");
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(selections, 1);
    expect(find.byType(SubscriptionLockerSheet), findsNothing);

    await _tapAllowanceText(tester, "+ 100 items on ");
    await tester.pumpAndSettle();
    expect(selections, 2);
    expect(find.byType(SubscriptionLockerSheet), findsNothing);

    await _tapAllowanceText(tester, "Locker");
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionLockerSheet), findsOneWidget);
    expect(selections, 2);

    await tester.tap(find.byTooltip("Close"));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionLockerSheet), findsNothing);

    tester.platformDispatcher.textScaleFactorTestValue = 3;
    await tester.pumpAndSettle();
    expect(find.text("Continue"), findsOneWidget);
    await tester.tap(find.text("Continue"));
    await tester.pumpAndSettle();
    expect(continues, 1);
  });
}

Future<void> _tapAllowanceText(WidgetTester tester, String text) async {
  final finder = find.descendant(
    of: find.text("+ 100 items on Locker"),
    matching: find.byType(RichText),
  );
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final start = paragraph.text.toPlainText().indexOf(text);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + text.length),
      )
      .single;
  await tester.tapAt(tester.getTopLeft(finder) + box.toRect().center);
}
