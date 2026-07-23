import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";

void main() {
  testWidgets("BannerComponent renders copy and handles taps", (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      _wrap(
        BannerComponent(
          title: "Subscribe",
          subtitle: "Your subscription has expired",
          state: BannerComponentState.failure,
          onTap: () => tapCount += 1,
        ),
      ),
    );

    expect(find.text("Subscribe"), findsOneWidget);
    expect(find.text("Your subscription has expired"), findsOneWidget);
    expect(find.byType(HugeIcon), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);

    final size = tester.getSize(
      find.byKey(const ValueKey("banner-component-surface")),
    );
    expect(size.width, 351);
    expect(size.height, greaterThanOrEqualTo(BannerComponent.minHeight));

    await tester.tap(find.text("Subscribe"));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets("BannerComponent supports no-subtitle banners", (tester) async {
    await tester.pumpWidget(
      _wrap(
        BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedAlertCircle,
          title: "Confirm your recovery key",
          onTap: () {},
        ),
      ),
    );

    final title = tester.widget<Text>(find.text("Confirm your recovery key"));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets("BannerComponent maps state colors from component tokens", (
    tester,
  ) async {
    await _expectTitleColor(
      tester,
      state: BannerComponentState.failure,
      title: "Failure",
      expectedColor: ComponentTheme.colorsForApp(ComponentApp.photos).warning,
    );
    await _expectTitleColor(
      tester,
      state: BannerComponentState.informative,
      title: "Informative",
      expectedColor: ComponentTheme.colorsForApp(ComponentApp.photos).blue,
    );
    await _expectTitleColor(
      tester,
      state: BannerComponentState.success,
      title: "Success",
      expectedColor: ComponentTheme.colorsForApp(
        ComponentApp.photos,
      ).primaryDark,
    );
    await _expectTitleColor(
      tester,
      state: BannerComponentState.warning,
      title: "Warning",
      expectedColor: ComponentTheme.colorsForApp(ComponentApp.photos).caution,
    );
    await _expectTitleColor(
      tester,
      state: BannerComponentState.neutral,
      title: "Neutral",
      expectedColor: ComponentTheme.colorsForApp(ComponentApp.photos).textBase,
    );
  });

  testWidgets("BannerComponent uses component surface styling", (tester) async {
    await tester.pumpWidget(
      _wrap(
        BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedDatabase,
          title: "Upgrade",
          subtitle: "Storage limit exceeded",
          state: BannerComponentState.failure,
          onTap: () {},
        ),
        brightness: Brightness.dark,
      ),
    );

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey("banner-component-surface")),
    );
    final decoration = surface.decoration as BoxDecoration;
    final colors = ComponentTheme.colorsForApp(
      ComponentApp.photos,
      brightness: Brightness.dark,
    );

    expect(decoration.color, colors.fillLight);
    expect(decoration.borderRadius, BorderRadius.circular(Radii.button));
    expect(decoration.boxShadow, isNull);
  });

  testWidgets("BannerComponent supports a custom trailing widget", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        BannerComponent(
          title: "Informative",
          subtitle: "Custom trailing affordance",
          state: BannerComponentState.informative,
          trailingWidget: const SizedBox(
            key: ValueKey("custom-trailing"),
            width: 24,
            height: 24,
            child: HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
          ),
          onTap: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey("custom-trailing")), findsOneWidget);
    final trailingSlotSize = tester.getSize(
      find.byKey(const ValueKey("banner-component-trailing-slot")),
    );
    expect(trailingSlotSize.width, BannerComponent.actionSize);
    expect(trailingSlotSize.height, BannerComponent.actionSize);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey("custom-trailing")),
        matching: find.byType(HugeIcon),
      ),
      findsOneWidget,
    );
    expect(find.byType(HugeIcon), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  testWidgets("BannerComponent supports a custom leading widget", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        BannerComponent(
          leadingIcon: HugeIcons.strokeRoundedInformationCircle,
          leadingWidget: const SizedBox(
            key: ValueKey("custom-leading"),
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: "Syncing",
          subtitle: "Preparing secure upload",
          state: BannerComponentState.informative,
          onTap: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey("custom-leading")), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(HugeIcon), findsNothing);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });
}

Future<void> _expectTitleColor(
  WidgetTester tester, {
  required BannerComponentState state,
  required String title,
  required Color expectedColor,
}) async {
  await tester.pumpWidget(
    _wrap(
      BannerComponent(
        leadingIcon: HugeIcons.strokeRoundedInformationCircle,
        title: title,
        state: state,
        onTap: () {},
      ),
    ),
  );

  final text = tester.widget<Text>(find.text(title));
  expect(text.style?.color, expectedColor);
}

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: ComponentTheme.themeForApp(
      ComponentApp.photos,
      brightness: brightness,
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: 351, child: child)),
    ),
  );
}
