import 'package:flutter/widgets.dart';
import 'package:photos/ui/viewer/gallery/swipe_to_select_helper.dart';

class GallerySwipeHelper extends InheritedWidget {
  final SwipeToSelectHelper? helper;
  final ValueNotifier<bool>? swipeActiveNotifier;

  const GallerySwipeHelper({
    super.key,
    this.helper,
    this.swipeActiveNotifier,
    required super.child,
  });

  static SwipeToSelectHelper? of(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<GallerySwipeHelper>();
    return widget?.helper;
  }

  static ValueNotifier<bool>? swipeActiveNotifierOf(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<GallerySwipeHelper>();
    return widget?.swipeActiveNotifier;
  }

  @override
  bool updateShouldNotify(GallerySwipeHelper oldWidget) {
    return helper != oldWidget.helper ||
        swipeActiveNotifier != oldWidget.swipeActiveNotifier;
  }
}
