import "dart:ui" as ui;

import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

class RewindShareCard {
  RewindShareCard({required this.branded});

  final boundary = GlobalKey();
  final bool branded;
  final stillFrame = ValueNotifier<ui.Image?>(null);
}

abstract interface class RewindNavigator {
  void next();

  void previous();

  void attachShareCard(RewindPage page, RewindShareCard card);

  void detachShareCard(RewindPage page, RewindShareCard card);

  void shareVideo(Rect? origin);
}

class RewindPageScope extends InheritedWidget {
  const RewindPageScope({
    required this.page,
    required this.navigator,
    required super.child,
    this.reel = false,
    super.key,
  });

  final RewindPage page;
  final RewindNavigator navigator;
  final bool reel;

  static RewindPageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RewindPageScope>();

  static bool reelOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RewindPageScope>()?.reel ?? false;

  static bool coveredOf(BuildContext context) =>
      !reelOf(context) && ModalRoute.of(context)?.isCurrent == false;

  static RewindNavigator? navigatorOf(BuildContext context) =>
      maybeOf(context)?.navigator;

  @override
  bool updateShouldNotify(RewindPageScope oldWidget) =>
      page != oldWidget.page ||
      navigator != oldWidget.navigator ||
      reel != oldWidget.reel;
}
