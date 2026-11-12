import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

class RewindShareCard {
  RewindShareCard({required this.branded});

  final boundary = GlobalKey();
  final bool branded;
}

abstract interface class RewindNavigator {
  void next();

  void previous();

  void attachShareCard(RewindPage page, RewindShareCard card);

  void detachShareCard(RewindPage page, RewindShareCard card);
}

class RewindPageScope extends InheritedWidget {
  const RewindPageScope({
    required this.page,
    required this.navigator,
    required super.child,
    super.key,
  });

  final RewindPage page;
  final RewindNavigator navigator;

  static RewindPageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RewindPageScope>();

  static RewindNavigator? navigatorOf(BuildContext context) =>
      maybeOf(context)?.navigator;

  @override
  bool updateShouldNotify(RewindPageScope oldWidget) =>
      page != oldWidget.page || navigator != oldWidget.navigator;
}
