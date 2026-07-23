import 'package:flutter/widgets.dart';
import 'package:photos/ui/viewer/gallery/swipe_to_select_helper.dart';

/// InheritedWidget to provide SwipeToSelectHelper to descendant widgets.
///
/// This allows GalleryFileWidget instances to access the swipe helper
/// without passing it through multiple widget constructors.
class GallerySwipeHelper extends InheritedWidget {
  final SwipeToSelectHelper? helper;
  final ValueNotifier<bool>? swipeActiveNotifier;

  const GallerySwipeHelper({
    super.key,
    this.helper,
    this.swipeActiveNotifier,
    required super.child,
  });

  /// Get the SwipeToSelectHelper from the nearest ancestor GallerySwipeHelper.
  static SwipeToSelectHelper? of(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<GallerySwipeHelper>();
    return widget?.helper;
  }

  /// Get the swipeActiveNotifier from the nearest ancestor GallerySwipeHelper.
  static ValueNotifier<bool>? swipeActiveNotifierOf(BuildContext context) {
    final widget = context
        .dependOnInheritedWidgetOfExactType<GallerySwipeHelper>();
    return widget?.swipeActiveNotifier;
  }

  @override
  bool updateShouldNotify(GallerySwipeHelper oldWidget) {
    // Notify if either the helper instance or notifier changes
    return helper != oldWidget.helper ||
        swipeActiveNotifier != oldWidget.swipeActiveNotifier;
  }
}
