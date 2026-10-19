import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/home/home_bottom_nav_bar.dart";
import "package:photos/ui/social/widgets/feed_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/received_empty_state.dart";

const _size = Size(402, 480);
const _bottomSafeArea = 34.0;

void main() {
  for (final (name, state) in <(String, Widget)>[
    (
      "Albums",
      const CustomScrollView(
        slivers: [SliverFillRemaining(child: ReceivedEmptyState())],
      ),
    ),
    ("Feed", const FeedEmptyState()),
  ]) {
    testWidgets("$name empty state scrolls its action clear of the nav bar", (
      tester,
    ) async {
      tester.view.physicalSize = _size * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: _size,
              padding: EdgeInsets.only(bottom: _bottomSafeArea),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: state),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      final action = find.byType(ButtonComponent);
      expect(action.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(action).bottom,
        lessThanOrEqualTo(
          _size.height - _bottomSafeArea - homeBottomNavigationBarHeight,
        ),
      );
    });
  }
}
