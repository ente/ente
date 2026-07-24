import 'dart:async';

import 'package:ente_components/components/app_bar_component.dart';
import 'package:ente_components/components/menu_component.dart';
import 'package:ente_components/components/menu_group_component.dart';
import 'package:ente_components/components/tooltip_component.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
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
  testWidgets('MenuComponent renders slots, states, and handles taps', (
    tester,
  ) async {
    var tapped = false;

    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Camera uploads',
        subtitle: 'Enabled on Wi-Fi',
        leading: const Icon(Icons.cloud_upload_outlined),
        trailing: Icon(
          Icons.chevron_right,
          color: ColorTokens.light.textLight,
          size: IconSizes.small,
        ),
        selected: true,
        titleColor: ColorTokens.light.warning,
        iconColor: ColorTokens.light.primary,
        onTap: () async => tapped = true,
      ),
    );

    expect(find.text('Camera uploads'), findsOneWidget);
    expect(find.text('Enabled on Wi-Fi'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(tester.getSize(find.byType(MenuComponent)).height, 60);
    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('menu-item-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(tester.widget<Text>(find.text('Camera uploads')).maxLines, 2);
    expect(tester.widget<Text>(find.text('Enabled on Wi-Fi')).maxLines, 2);
    expect(
      tester.widget<Text>(find.text('Camera uploads')).style?.color,
      ColorTokens.light.warning,
    );
    expect(
      IconTheme.of(
        tester.element(find.byIcon(Icons.cloud_upload_outlined)),
      ).color,
      ColorTokens.light.primary,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.chevron_right)).color,
      ColorTokens.light.textLight,
    );

    await tester.tap(find.text('Camera uploads'));
    await tester.pump();
    expect(tapped, isTrue);
  });

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

  testWidgets('MenuComponent can show only loading without success', (
    tester,
  ) async {
    final completer = Completer<void>();

    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Refresh',
        showOnlyLoadingState: true,
        onTap: () => completer.future,
      ),
    );

    await tester.tap(find.text('Refresh'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('menu-item-loading')), findsOneWidget);

    completer.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-item-success')), findsNothing);
    expect(find.byKey(const ValueKey('menu-item-loading')), findsNothing);
  });

  testWidgets('MenuComponent can force success for fast actions', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Copy',
        shouldSurfaceExecutionStates: true,
        shouldShowSuccessConfirmation: true,
        onTap: () async {},
      ),
    );

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-item-success')), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('menu-item-success')), findsNothing);
  });

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

  testWidgets('MenuComponent can disable gestures for display-only rows', (
    tester,
  ) async {
    var tapCount = 0;

    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Storage plan',
        isDisabled: true,
        onTap: () {
          tapCount += 1;
        },
      ),
    );

    await tester.tap(find.text('Storage plan'));
    await tester.pump();
    expect(tapCount, 0);
  });

  testWidgets('MenuComponent handles double tap gestures', (tester) async {
    var doubleTapCount = 0;

    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Verify email',
        onDoubleTap: () => doubleTapCount += 1,
      ),
    );

    await tester.tap(find.text('Verify email'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Verify email'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(doubleTapCount, 1);
  });

  testWidgets('MenuComponent handles long press gestures', (tester) async {
    var longPressCount = 0;

    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Share logs',
        onLongPress: () => longPressCount += 1,
      ),
    );

    await tester.longPress(find.text('Share logs'));
    await tester.pump();

    expect(longPressCount, 1);
  });

  testWidgets('MenuComponent disables double tap and long press gestures', (
    tester,
  ) async {
    var doubleTapCount = 0;
    var longPressCount = 0;

    await pumpComponent(
      tester,
      MenuComponent(
        title: 'Disabled row',
        isDisabled: true,
        onDoubleTap: () => doubleTapCount += 1,
        onLongPress: () => longPressCount += 1,
      ),
    );

    await tester.tap(find.text('Disabled row'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Disabled row'));
    await tester.pump();
    await tester.longPress(find.text('Disabled row'));
    await tester.pump();

    expect(doubleTapCount, 0);
    expect(longPressCount, 0);
  });

  testWidgets('MenuGroupComponent shapes a list of menu items', (tester) async {
    var tapped = false;
    var disabledTapped = false;

    await pumpComponent(
      tester,
      MenuGroupComponent(
        backgroundColor: Colors.orange,
        items: [
          MenuComponent(
            title: 'Account',
            leading: const Icon(Icons.person_outline),
            selected: true,
            titleColor: ColorTokens.light.warning,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => tapped = true,
          ),
          MenuComponent(
            title: 'Security',
            leading: const Icon(Icons.lock_outline),
            isDisabled: true,
            onTap: () => disabledTapped = true,
          ),
          const MenuComponent(
            title: 'Appearance',
            leading: Icon(Icons.palette_outlined),
          ),
        ],
      ),
      height: 180,
    );

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Account')).style?.color,
      ColorTokens.light.warning,
    );

    final groupSurface = tester.widget<Container>(
      find.byKey(const ValueKey('menu-group-surface')),
    );
    final groupDecoration = groupSurface.decoration! as BoxDecoration;
    expect(
      groupDecoration.borderRadius,
      const BorderRadius.all(Radius.circular(20)),
    );

    final itemSurfaces = tester.widgetList<AnimatedContainer>(
      find.byKey(const ValueKey('menu-item-surface')),
    );
    final itemRadii = itemSurfaces
        .map((surface) => (surface.decoration! as BoxDecoration).borderRadius)
        .toList();
    final itemColors = itemSurfaces
        .map((surface) => (surface.decoration! as BoxDecoration).color)
        .toList();

    expect(itemRadii[0], const BorderRadius.vertical(top: Radius.circular(20)));
    expect(itemRadii[1], BorderRadius.zero);
    expect(
      itemRadii[2],
      const BorderRadius.vertical(bottom: Radius.circular(20)),
    );
    expect(itemColors, everyElement(Colors.orange));

    await tester.tap(find.text('Account'));
    await tester.tap(find.text('Security'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(disabledTapped, isFalse);
  });

  testWidgets('MenuComponent supports pressed and execution visuals', (
    tester,
  ) async {
    final loadingCompleter = Completer<void>();
    var tapCount = 0;
    await pumpComponent(
      tester,
      Column(
        children: [
          MenuComponent(
            title: 'Pressed row',
            onTap: () {
              tapCount += 1;
            },
          ),
          MenuComponent(
            title: 'Loading row',
            trailing: const Icon(Icons.chevron_right),
            showOnlyLoadingState: true,
            shouldSurfaceExecutionStates: true,
            onTap: () => loadingCompleter.future,
          ),
          MenuComponent(
            title: 'Success row',
            trailing: const Icon(Icons.chevron_right),
            shouldSurfaceExecutionStates: true,
            shouldShowSuccessConfirmation: true,
            onTap: () async {},
          ),
        ],
      ),
      height: 180,
    );

    await tester.press(find.text('Pressed row'));
    await tester.pump();
    await tester.tap(find.text('Loading row'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Success row'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final surfaces = tester.widgetList<AnimatedContainer>(
      find.byKey(const ValueKey('menu-item-surface')),
    );
    final pressedDecoration = surfaces.first.decoration! as BoxDecoration;
    expect(pressedDecoration.color, ColorTokens.light.fillDarker);
    expect(find.byKey(const ValueKey('menu-item-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-success')), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tapCount, 0);
    loadingCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('MenuComponent allows two subtitle lines for one-line titles', (
    tester,
  ) async {
    const subtitle =
        'This subtitle can use two lines when the title fits on one line';

    await pumpComponent(
      tester,
      const MenuComponent(
        title: 'Camera uploads',
        subtitle: subtitle,
        leading: Icon(Icons.image_outlined),
        trailing: Icon(Icons.chevron_right),
      ),
      width: 320,
    );

    expect(tester.widget<Text>(find.text('Camera uploads')).maxLines, 2);
    expect(tester.widget<Text>(find.text(subtitle)).maxLines, 2);
    expect(tester.getSize(find.byType(MenuComponent)).height, greaterThan(60));
  });

  testWidgets('MenuComponent long text uses two title lines and one subtitle line', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const MenuComponent(
        title:
            'Camera uploads from this device and shared albums waiting for review',
        subtitle:
            'This subtitle remains one line and truncates like app menu rows',
        leading: Icon(Icons.image_outlined),
        trailing: Icon(Icons.chevron_right),
      ),
      width: 260,
    );

    expect(
      tester
          .widget<Text>(
            find.text(
              'Camera uploads from this device and shared albums waiting for review',
            ),
          )
          .maxLines,
      2,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'This subtitle remains one line and truncates like app menu rows',
            ),
          )
          .maxLines,
      1,
    );
    expect(tester.getSize(find.byType(MenuComponent)).height, greaterThan(60));
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

  testWidgets('SliverAppBarComponent can disable tap tooltip title reveal', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          const SliverAppBarComponent(
            title: 'Aman',
            disableTitleTapReveal: true,
            actions: [Icon(Icons.search)],
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

    expect(find.byType(TooltipComponent), findsNothing);
    expect(find.byType(TooltipBubbleComponent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SliverAppBarComponent preserves tap-only title callbacks', (
    tester,
  ) async {
    var tapped = false;

    await pumpComponent(
      tester,
      CustomScrollView(
        slivers: [
          SliverAppBarComponent(
            title: 'Tap me',
            onTitleTap: () => tapped = true,
            actions: const [Icon(Icons.search)],
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

    expect(find.byType(TooltipComponent), findsNothing);

    await tester.tap(find.text('Tap me'));
    await tester.pump();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TooltipBubbleComponent renders top pointer bubble', (
    tester,
  ) async {
    await pumpComponent(
      tester,
      const TooltipBubbleComponent(message: 'Tooltip text'),
      width: 390,
      height: 200,
    );

    expect(find.byType(TooltipBubbleComponent), findsOneWidget);
    final tooltipText = tester.widget<Text>(find.text('Tooltip text'));
    expect(tooltipText.style?.fontSize, 12);
    expect(tooltipText.style?.fontWeight, FontWeight.w500);
    expect(tooltipText.style?.height, 16 / 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'SliverAppBarComponent collapse progress matches reserved space',
    (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await pumpComponent(
        tester,
        CustomScrollView(
          controller: scrollController,
          slivers: [
            const SliverAppBarComponent(
              title: 'Menu items',
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

      scrollController.jumpTo(48);
      await tester.pump();

      final title = tester.widget<Text>(find.text('Menu items'));
      expect(title.style?.fontSize, greaterThan(16));
      expect(title.style?.fontFamily, TextStyles.display2.fontFamily);

      scrollController.jumpTo(74);
      await tester.pump();

      final collapsedTitle = tester.widget<Text>(find.text('Menu items'));
      expect(collapsedTitle.style?.fontSize, closeTo(20, 0.01));
      expect(collapsedTitle.style?.fontFamily, TextStyles.display3.fontFamily);
      expect(tester.getTopLeft(find.text('Item 0')).dy, closeTo(56, 1));
    },
  );

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
