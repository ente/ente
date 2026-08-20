import 'dart:async';
import 'dart:ui';

import 'package:ente_components/components/app_bar_component.dart';
import 'package:ente_components/components/menu_component.dart';
import 'package:ente_components/components/tooltip_component.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpComponent(
  WidgetTester tester,
  Widget child, {
  double width = 420,
  double? height,
  TextScaler textScaler = TextScaler.noScaling,
  bool boldText = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ComponentTheme.lightTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler, boldText: boldText),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, height: height, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'MenuComponent delays loading, blocks repeat taps, and shows success',
    (tester) async {
      final completer = Completer<void>();
      var tapCount = 0;

      await pumpComponent(
        tester,
        MenuComponent(
          title: 'Sync now',
          trailing: const Icon(Icons.chevron_right),
          shouldSurfaceExecutionStates: true,
          onTap: () {
            tapCount += 1;
            return completer.future;
          },
        ),
      );

      await tester.tap(find.text('Sync now'));
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.byKey(const ValueKey('menu-item-loading')), findsNothing);

      await tester.tap(find.text('Sync now'));
      await tester.pump(const Duration(milliseconds: 1));
      expect(tapCount, 1);
      expect(find.byKey(const ValueKey('menu-item-loading')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      completer.complete();
      await tester.pump();
      expect(find.byKey(const ValueKey('menu-item-success')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('menu-item-loading')), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    },
  );

  testWidgets(
    'MenuComponent clears hover after returning from a pushed route',
    (tester) async {
      await pumpComponent(
        tester,
        Builder(
          builder: (context) => MenuComponent(
            title: 'Security',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Submenu')),
              ),
            ),
          ),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Security')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Security'));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();

      Navigator.of(tester.element(find.text('Submenu'))).pop();
      await tester.pumpAndSettle();

      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('menu-item-surface')),
      );
      expect(
        (surface.decoration! as BoxDecoration).color,
        ColorTokens.light.fillLight,
      );
    },
  );

  testWidgets('MenuComponent resets to idle after async errors', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Fail',
        trailing: const Icon(Icons.chevron_right),
        shouldSurfaceExecutionStates: true,
        onTap: () async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          throw StateError('failed');
        },
      ),
    );

    await tester.tap(find.text('Fail'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('menu-item-loading')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Fail'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-loading')), findsNothing);
    expect(find.byKey(const ValueKey('menu-item-success')), findsNothing);
  });

  testWidgets('SliverAppBarComponent scrolls without narrow width overflow', (
    tester,
  ) async {
    var addTapped = false;
    var leadingTapped = false;

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          SliverAppBarComponent(
            title: 'Menu items',
            subtitle: 'Scroll to collapse',
            onBack: () {},
            leading: GestureDetector(
              key: const ValueKey('header-leading'),
              behavior: HitTestBehavior.opaque,
              onTap: () => leadingTapped = true,
              child: const ColoredBox(color: Colors.blue),
            ),
            actions: [
              GestureDetector(
                key: const ValueKey('header-add-action'),
                behavior: HitTestBehavior.opaque,
                onTap: () => addTapped = true,
                child: const Icon(Icons.add),
              ),
              const Icon(Icons.dark_mode),
            ],
          ),
          SliverList.builder(
            itemCount: 24,
            itemBuilder: (context, index) {
              return SizedBox(height: 60, child: Text('Item $index'));
            },
          ),
        ],
      ),
      width: 390,
      height: 600,
    );

    expect(tester.takeException(), isNull);
    expect(tester.getCenter(find.byIcon(Icons.arrow_back)).dy, closeTo(28, 1));
    expect(tester.getSize(find.byIcon(Icons.arrow_back)).width, 24);
    expect(
      tester.getSize(find.byKey(const ValueKey('header-leading'))),
      const Size(38, 38),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('header-leading'))).dy,
      closeTo(89, 1),
    );
    expect(tester.getCenter(find.byIcon(Icons.add)).dy, closeTo(89, 1));

    await tester.tap(find.byKey(const ValueKey('header-leading')));
    await tester.pump();
    expect(leadingTapped, isTrue);

    await tester.tap(find.byKey(const ValueKey('header-add-action')));
    await tester.pump();
    expect(addTapped, isTrue);

    for (var index = 0; index < 8; index++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -24));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pump();

    leadingTapped = false;
    await tester.tap(
      find.byKey(const ValueKey('header-leading')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(leadingTapped, isFalse);
    expect(
      tester.getCenter(find.byIcon(Icons.add)).dy,
      closeTo(tester.getCenter(find.byIcon(Icons.arrow_back)).dy, 1),
    );
    expect(find.text('Menu items'), findsWidgets);
  });

  testWidgets('SliverAppBarComponent supports tap tooltip title reveal', (
    tester,
  ) async {
    const title = 'Aman';

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          const SliverAppBarComponent(
            title: title,
            actions: [Icon(Icons.search), Icon(Icons.more_vert)],
          ),
          SliverList.builder(
            itemCount: 8,
            itemBuilder: (context, index) {
              return SizedBox(height: 60, child: Text('Item $index'));
            },
          ),
        ],
      ),
      width: 320,
      height: 360,
    );

    expect(find.byType(TooltipComponent), findsOneWidget);
    expect(tester.getSize(find.byType(TooltipComponent)).width, lessThan(160));
    expect(find.byType(TooltipBubbleComponent), findsNothing);

    await tester.tap(find.byType(TooltipComponent));
    await tester.pump();

    expect(find.byType(TooltipBubbleComponent), findsOneWidget);
    expect(
      tester.getSize(find.byType(TooltipBubbleComponent)).width,
      lessThan(160),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SliverAppBarComponent measures titles with bold text style', (
    tester,
  ) async {
    const title = 'Summer Vacation';

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          const SliverAppBarComponent(
            title: title,
            actions: [Icon(Icons.more_vert)],
          ),
          SliverList.builder(
            itemCount: 8,
            itemBuilder: (context, index) {
              return SizedBox(height: 60, child: Text('Item $index'));
            },
          ),
        ],
      ),
      width: 320,
      height: 360,
      boldText: true,
    );

    expect(
      tester.widget<Text>(find.text(title)).style?.fontWeight,
      FontWeight.bold,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SliverAppBarComponent keeps tap tooltip with title gestures', (
    tester,
  ) async {
    var longPressed = false;

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          SliverAppBarComponent(
            title: 'aman@example.com',
            onTitleLongPress: () => longPressed = true,
            actions: const [Icon(Icons.search), Icon(Icons.more_vert)],
          ),
          SliverList.builder(
            itemCount: 8,
            itemBuilder: (context, index) {
              return SizedBox(height: 60, child: Text('Item $index'));
            },
          ),
        ],
      ),
      width: 320,
      height: 360,
    );

    expect(find.byType(TooltipComponent), findsOneWidget);
    expect(find.byType(TooltipBubbleComponent), findsNothing);

    await tester.tap(find.byType(TooltipComponent));
    await tester.pump();

    expect(find.byType(TooltipBubbleComponent), findsOneWidget);
    expect(longPressed, isFalse);

    await tester.tapAt(Offset.zero);
    await tester.pump();

    await tester.longPress(find.byType(TooltipComponent));
    await tester.pump();

    expect(longPressed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SliverAppBarComponent collapses title content and reserved space',
    (tester) async {
      const eyebrowText = 'Sharing with a long translated context';
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await pumpComponent(
        tester,
        CustomScrollView(
          controller: scrollController,
          slivers: [
            const SliverAppBarComponent(
              title: 'Priyadarshini Bandopadhyay',
              eyebrow: eyebrowText,
              subtitle: 'Scroll to collapse',
              onBack: null,
              actions: [Icon(Icons.add)],
            ),
            SliverList.builder(
              itemCount: 24,
              itemBuilder: (context, index) {
                return SizedBox(height: 60, child: Text('Item $index'));
              },
            ),
          ],
        ),
        width: 390,
        height: 600,
      );

      final eyebrow = find.text(eyebrowText);
      final titleFinder = find.text('Priyadarshini Bandopadhyay');
      expect(
        tester.getTopLeft(eyebrow).dy,
        lessThan(tester.getTopLeft(titleFinder).dy),
      );

      scrollController.jumpTo(48);
      await tester.pump();

      final title = tester.widget<Text>(titleFinder);
      expect(title.style?.fontSize, greaterThan(16));
      expect(title.style?.fontFamily, TextStyles.display2.fontFamily);

      scrollController.jumpTo(104);
      await tester.pump();

      final collapsedTitle = tester.widget<Text>(titleFinder);
      expect(collapsedTitle.style?.fontSize, closeTo(20, 0.01));
      expect(collapsedTitle.style?.fontFamily, TextStyles.display3.fontFamily);
      expect(collapsedTitle.overflow, TextOverflow.ellipsis);
      expect(
        tester.getTopLeft(eyebrow).dy,
        closeTo(tester.getTopLeft(titleFinder).dy, 0.5),
      );
      expect(
        tester.getTopRight(eyebrow).dx,
        lessThanOrEqualTo(tester.getTopLeft(titleFinder).dx),
      );
      expect(tester.getTopLeft(find.text('Item 0')).dy, closeTo(56, 1));
    },
  );

  testWidgets('SliverAppBarComponent reserves custom title height', (
    tester,
  ) async {
    const customTitleKey = ValueKey('custom-title');
    const firstItemKey = ValueKey('first-item');

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          SliverAppBarComponent(
            title: 'Custom title',
            titleBuilderHeight: 80,
            titleBuilder: (_, _) =>
                const SizedBox(key: customTitleKey, height: 80),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(key: firstItemKey, height: 80),
          ),
        ],
      ),
      width: 390,
      height: 600,
    );

    expect(
      tester.getBottomLeft(find.byKey(customTitleKey)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(firstItemKey)).dy),
    );
  });

  testWidgets('AppBarComponent lets short content stick collapsed', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await pumpComponent(
      tester,
      AppBarComponent(
        controller: scrollController,
        title: 'Appearance',
        subtitle: 'Settings',
        actions: const [Icon(Icons.dark_mode)],
        slivers: const [
          SliverToBoxAdapter(
            child: SizedBox(height: 80, child: Text('System theme')),
          ),
        ],
      ),
      width: 390,
      height: 600,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(scrollController.offset, closeTo(74, 1));
    final collapsedTitle = tester.widget<Text>(find.text('Appearance'));
    expect(collapsedTitle.style?.fontSize, closeTo(20, 0.01));
    expect(collapsedTitle.style?.fontFamily, TextStyles.display3.fontFamily);
    expect(tester.getTopLeft(find.text('System theme')).dy, closeTo(56, 1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 32));
    await tester.pumpAndSettle();
    expect(scrollController.offset, closeTo(74, 1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(scrollController.offset, closeTo(0, 1));
  });

  testWidgets('AppBarComponent updates header colors when theme changes', (
    tester,
  ) async {
    Widget buildWithTheme(ThemeMode themeMode) {
      return MaterialApp(
        theme: ComponentTheme.lightTheme(),
        darkTheme: ComponentTheme.darkTheme(),
        themeMode: themeMode,
        home: const MediaQuery(
          data: MediaQueryData(),
          child: Scaffold(
            body: AppBarComponent(
              title: 'Appearance',
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: 80, child: Text('Theme')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Color headerColor() {
      final headerBackground = find.descendant(
        of: find.byType(SliverPersistentHeader),
        matching: find.byType(ColoredBox),
      );
      return tester.widget<ColoredBox>(headerBackground.first).color;
    }

    await tester.pumpWidget(buildWithTheme(ThemeMode.light));
    await tester.pump();
    expect(headerColor(), ColorTokens.light.backgroundBase);

    await tester.pumpWidget(buildWithTheme(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(headerColor(), ColorTokens.dark.backgroundBase);
  });

  testWidgets('SliverAppBarComponent adapts vertical space for large text', (
    tester,
  ) async {
    const title = 'A very large header title that should stay constrained';

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          const SliverAppBarComponent(
            title: title,
            subtitle: 'Large text subtitle',
            onBack: null,
            actions: [Icon(Icons.add)],
          ),
          SliverList.builder(
            itemCount: 12,
            itemBuilder: (context, index) {
              return SizedBox(height: 60, child: Text('Scaled item $index'));
            },
          ),
        ],
      ),
      width: 390,
      height: 600,
      textScaler: const TextScaler.linear(2.5),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(title), findsOneWidget);
    expect(tester.getBottomLeft(find.text(title)).dy, lessThanOrEqualTo(128));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(title), findsOneWidget);
  });
}
