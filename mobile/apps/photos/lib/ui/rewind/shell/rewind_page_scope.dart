import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";

class RewindShareCard {
  RewindShareCard({required this.branded, required this.onShare});

  final boundary = GlobalKey();
  final bool branded;
  final VoidCallback onShare;
  final stillFrame = ValueNotifier<ui.Image?>(null);
}

abstract interface class RewindNavigator {
  void next();

  void previous();

  void attachShareCard(RewindPage page, RewindShareCard card);

  void detachShareCard(RewindPage page, RewindShareCard card);

  void shareVideo(Rect? origin);

  ValueListenable<bool> get videoSaved;

  void saveVideo();
}

class RewindPageScope extends InheritedWidget {
  const RewindPageScope({
    required this.page,
    required this.navigator,
    required super.child,
    this.reel = false,
    this.clip = false,
    super.key,
  });

  final RewindPage page;
  final RewindNavigator navigator;
  final bool reel;
  final bool clip;

  static RewindPageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RewindPageScope>();

  static bool reelOf(BuildContext context) => _of(context)?.reel ?? false;

  static bool clipOf(BuildContext context) => _of(context)?.clip ?? false;

  static bool reelPaceOf(BuildContext context) =>
      reelOf(context) && !clipOf(context);

  static RewindPageScope? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RewindPageScope>();

  static bool coveredOf(BuildContext context) =>
      !reelOf(context) && ModalRoute.of(context)?.isCurrent == false;

  static RewindNavigator? navigatorOf(BuildContext context) =>
      maybeOf(context)?.navigator;

  @override
  bool updateShouldNotify(RewindPageScope oldWidget) =>
      page != oldWidget.page ||
      navigator != oldWidget.navigator ||
      reel != oldWidget.reel ||
      clip != oldWidget.clip;
}
