import 'package:flutter/material.dart';

/// StatefulWidget that manages gallery boundaries and scroll controller lifecycle
class GalleryBoundariesProvider extends StatefulWidget {
  final Widget child;

  const GalleryBoundariesProvider({super.key, required this.child});

  @override
  State<GalleryBoundariesProvider> createState() =>
      GalleryBoundariesProviderState();

  static InheritedGalleryBoundaries? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedGalleryBoundaries>();
  }
}

/// State class that manages the lifecycle of boundary notifiers
class GalleryBoundariesProviderState extends State<GalleryBoundariesProvider> {
  /// Bottom edge position of the top fixed widget (e.g., AppBar)
  late final ValueNotifier<double?> topBoundaryNotifier;

  /// Top edge position of the bottom fixed widget (e.g., FileSelectionOverlayBar)
  late final ValueNotifier<double?> bottomBoundaryNotifier;

  /// Reference to Gallery's ScrollController
  /// Using ValueNotifier to maintain immutability
  late final ValueNotifier<ScrollController?> scrollControllerNotifier;

  @override
  void initState() {
    super.initState();
    topBoundaryNotifier = ValueNotifier<double?>(null);
    bottomBoundaryNotifier = ValueNotifier<double?>(null);
    scrollControllerNotifier = ValueNotifier<ScrollController?>(null);
  }

  @override
  void dispose() {
    topBoundaryNotifier.dispose();
    bottomBoundaryNotifier.dispose();
    scrollControllerNotifier.dispose();
    super.dispose();
  }

  /// Set the scroll controller from Gallery widget
  void setScrollController(ScrollController? controller) {
    scrollControllerNotifier.value = controller;
  }

  /// Set the top boundary position
  void setTopBoundary(double? boundary) {
    topBoundaryNotifier.value = boundary;
  }

  /// Set the bottom boundary position
  void setBottomBoundary(double? boundary) {
    bottomBoundaryNotifier.value = boundary;
  }

  @override
  Widget build(BuildContext context) {
    return InheritedGalleryBoundaries(state: this, child: widget.child);
  }
}

/// Public InheritedWidget to share gallery boundaries and scroll controller
/// between Gallery and its surrounding widgets for auto-scroll functionality
class InheritedGalleryBoundaries extends InheritedWidget {
  final GalleryBoundariesProviderState state;

  const InheritedGalleryBoundaries({
    super.key,
    required this.state,
    required super.child,
  });

  /// Bottom edge position of the top fixed widget (e.g., AppBar)
  ValueNotifier<double?> get topBoundaryNotifier => state.topBoundaryNotifier;

  /// Top edge position of the bottom fixed widget (e.g., FileSelectionOverlayBar)
  ValueNotifier<double?> get bottomBoundaryNotifier =>
      state.bottomBoundaryNotifier;

  /// Reference to Gallery's ScrollController
  ValueNotifier<ScrollController?> get scrollControllerNotifier =>
      state.scrollControllerNotifier;

  /// Set the scroll controller from Gallery widget
  void setScrollController(ScrollController? controller) {
    state.setScrollController(controller);
  }

  /// Set the top boundary position
  void setTopBoundary(double? boundary) {
    state.setTopBoundary(boundary);
  }

  /// Set the bottom boundary position
  void setBottomBoundary(double? boundary) {
    state.setBottomBoundary(boundary);
  }

  @override
  bool updateShouldNotify(InheritedGalleryBoundaries oldWidget) {
    return false;
  }
}
