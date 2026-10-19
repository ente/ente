import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

Future<T?> routeToPage<T extends Object>(
  BuildContext context,
  Widget page, {
  bool forceCustomPageRoute = false,
  bool useFadeTransition = false,
}) {
  if (Platform.isAndroid || forceCustomPageRoute) {
    return Navigator.of(context).push(_buildPageRoute(page));
  } else {
    return Navigator.of(context).push(
      SwipeableRouteBuilder(
        useFadeTransition: useFadeTransition,
        pageBuilder: (context, animation, secondaryAnimation) {
          return page;
        },
      ),
    );
  }
}

void replacePage(BuildContext context, Widget page, {Object? result}) {
  Navigator.of(context).pushReplacement(_buildPageRoute(page), result: result);
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

class SwipeableRouteBuilder<T> extends PageRoute<T> {
  final RoutePageBuilder pageBuilder;
  final bool useFadeTransition;
  // Cupertino preserves the iOS back-swipe gesture.
  final PageTransitionsBuilder matchingBuilder =
      const CupertinoPageTransitionsBuilder();

  SwipeableRouteBuilder({
    required this.pageBuilder,
    this.useFadeTransition = false,
  });

  @override
  Null get barrierColor => null;

  @override
  Null get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return pageBuilder(context, animation, secondaryAnimation);
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => useFadeTransition
      ? const Duration(milliseconds: 200)
      : const Duration(milliseconds: 300);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final transition = matchingBuilder.buildTransitions<T>(
      this,
      context,
      useFadeTransition ? kAlwaysCompleteAnimation : animation,
      useFadeTransition ? kAlwaysDismissedAnimation : secondaryAnimation,
      child,
    );
    return useFadeTransition
        ? FadeTransition(opacity: animation, child: transition)
        : transition;
  }

  @override
  bool get opaque => false;
}

class TransparentRoute extends PageRoute<void> {
  TransparentRoute({required this.builder, super.settings})
    : assert(builder != null),
      super(fullscreenDialog: false);

  final WidgetBuilder? builder;

  @override
  bool get opaque => false;

  @override
  Null get barrierColor => null;

  @override
  Null get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final result = builder!(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(animation),
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: result,
      ),
    );
  }
}
