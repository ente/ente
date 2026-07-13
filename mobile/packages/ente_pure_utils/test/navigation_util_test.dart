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
}
