import 'package:flutter/material.dart';

class MenuComponentSurfaceStyle extends InheritedWidget {
  const MenuComponentSurfaceStyle({
    super.key,
    required super.child,
    this.borderRadius,
    this.backgroundColor,
  });

  final BorderRadius? borderRadius;
  final Color? backgroundColor;

  static MenuComponentSurfaceStyle? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MenuComponentSurfaceStyle>();
  }

  @override
  bool updateShouldNotify(covariant MenuComponentSurfaceStyle oldWidget) {
    return oldWidget.borderRadius != borderRadius ||
        oldWidget.backgroundColor != backgroundColor;
  }
}
