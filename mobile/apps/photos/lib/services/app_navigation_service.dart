import 'dart:async';
import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

// External entry points must use the inner Photos navigator. A BuildContext may
// resolve to AppLock's outer navigator while the app is locked or resuming.
// Ordinary in-app navigation should use its local context.
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

  // The inner navigator may be unavailable while AppLock rebuilds after resume.
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
