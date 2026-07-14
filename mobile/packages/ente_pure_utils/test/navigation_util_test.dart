import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('swipe route only pairs its outgoing slide with swipe routes', () {
    final swipeRoute = SwipeableRouteBuilder<void>(
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final nextSwipeRoute = SwipeableRouteBuilder<void>(
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    final fadeRoute = PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    expect(swipeRoute.canTransitionTo(nextSwipeRoute), isTrue);
    expect(swipeRoute.canTransitionTo(fadeRoute), isFalse);
  });

  testWidgets('routeToPage keeps replace and remove-until stack behavior', (
    tester,
  ) async {
    late BuildContext context;
    final observer = _NavigationObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (builderContext) {
            context = builderContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    routeToPage(context, const SizedBox.shrink()).ignore();
    await tester.pumpAndSettle();
    routeToPage(
      context,
      const SizedBox.shrink(),
      replaceCurrent: true,
    ).ignore();
    await tester.pumpAndSettle();
    expect(observer.replacedRoutes, 1);

    routeToPage(context, const SizedBox.shrink()).ignore();
    await tester.pumpAndSettle();
    routeToPage(
      context,
      const SizedBox.shrink(),
      removeUntil: (route) => route.isFirst,
    ).ignore();
    await tester.pumpAndSettle();
    expect(observer.removedRoutes, 2);
  });
}

class _NavigationObserver extends NavigatorObserver {
  int removedRoutes = 0;
  int replacedRoutes = 0;

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removedRoutes++;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacedRoutes++;
  }
}
