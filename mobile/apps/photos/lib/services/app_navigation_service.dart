import 'dart:async';
import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

/// Routes pages onto the inner Photos app navigator.
///
/// The Photos app is currently wrapped by an outer `AppLock` `MaterialApp`
/// that owns the lock-screen navigator, while `EnteApp` creates the real app
/// `MaterialApp` inside it. External entry points such as widgets and
/// notifications can arrive while the app is backgrounded and locked. In those
/// cases, a random `BuildContext` may resolve to the outer lock navigator,
/// causing the destination page to be pushed on the wrong stack.
///
/// Use this service for navigation that must land on the actual app stack even
/// when the app is resuming from background, opening from a widget, or handling
/// a notification/deep link without a reliable inner-app `BuildContext`.
///
/// Do not use this service for ordinary in-app navigation where a local page
/// context is already available and intentionally scoped to the current nested
/// navigator tree.
class AppNavigationService {
  AppNavigationService._privateConstructor();

  static final AppNavigationService instance =
      AppNavigationService._privateConstructor();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Logger _logger = Logger("AppNavigationService");
  // Serialize push initiation so multi-step external launches keep their
  // intended stack order even when navigator attachment is delayed by unlock.
  Future<void> _lastScheduledPush = Future<void>.value();

  NavigatorState? get navigator => navigatorKey.currentState;

  /// Pushes a page onto the inner app navigator.
  ///
  /// This waits briefly for the inner `MaterialApp` to finish rebuilding during
  /// resume/unlock so callers from widget and notification handlers do not have
  /// to coordinate navigator readiness themselves. Push requests are scheduled
  /// in call order so stacked routes do not race each other during resume.
  Future<T?> pushPage<T extends Object>(
    Widget page, {
    bool forceCustomPageRoute = false,
  }) {
    final pushResult = Completer<T?>();
    final scheduledPush = _lastScheduledPush
        .catchError((Object _, StackTrace _) {})
        .then((_) async {
          final navigator = await _waitForNavigator();
          if (navigator == null) {
            _logger.warning(
              "Skipping navigation because app navigator is unavailable",
            );
            if (!pushResult.isCompleted) {
              pushResult.complete(null);
            }
            return;
          }

          try {
            final routeFuture = _pushWithNavigator<T>(
              navigator,
              page,
              forceCustomPageRoute: forceCustomPageRoute,
            );
            unawaited(
              routeFuture.then(
                (value) {
                  if (!pushResult.isCompleted) {
                    pushResult.complete(value);
                  }
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (!pushResult.isCompleted) {
                    pushResult.completeError(error, stackTrace);
                  }
                },
              ),
            );
          } catch (error, stackTrace) {
            if (!pushResult.isCompleted) {
              pushResult.completeError(error, stackTrace);
            }
            rethrow;
          }
        });
    _lastScheduledPush = scheduledPush.catchError((Object _, StackTrace _) {});
    return pushResult.future;
  }

  Future<T?> _pushWithNavigator<T extends Object>(
    NavigatorState navigator,
    Widget page, {
    bool forceCustomPageRoute = false,
  }) {
    if (Platform.isAndroid || forceCustomPageRoute) {
      return navigator.push(_buildPageRoute(page));
    }

    return navigator.push(
      SwipeableRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return page;
        },
      ),
    );
  }

  /// The inner navigator can be temporarily unavailable while Flutter is
  /// restoring the app tree after resume or unlock. Wait on frame boundaries
  /// so external launch handlers can navigate after the app tree is rebuilt.
  Future<NavigatorState?> _waitForNavigator() async {
    final binding = WidgetsBinding.instance;
    for (var attempt = 0; attempt < 120; attempt++) {
      final currentNavigator = navigator;
      if (currentNavigator != null) {
        return currentNavigator;
      }
      binding.ensureVisualUpdate();
      await binding.endOfFrame;
    }
    _logger.warning("Inner navigator did not become ready in time");
    return null;
  }
}

PageRouteBuilder<T> _buildPageRoute<T extends Object>(Widget page) {
  return PageRouteBuilder(
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) {
          return page;
        },
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          return Align(
            child: FadeTransition(opacity: animation, child: child),
          );
        },
    transitionDuration: const Duration(milliseconds: 200),
    opaque: false,
  );
}
