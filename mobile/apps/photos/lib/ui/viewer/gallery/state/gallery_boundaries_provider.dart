import 'package:flutter/material.dart';

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

class GalleryBoundariesProviderState extends State<GalleryBoundariesProvider> {
  // Bottom edge of the top fixed widget.
  late final ValueNotifier<double?> topBoundaryNotifier;

  // Top edge of the bottom fixed widget.
  late final ValueNotifier<double?> bottomBoundaryNotifier;

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

  void setScrollController(ScrollController? controller) {
    scrollControllerNotifier.value = controller;
  }

  void setTopBoundary(double? boundary) {
    topBoundaryNotifier.value = boundary;
  }

  void setBottomBoundary(double? boundary) {
    bottomBoundaryNotifier.value = boundary;
  }

  @override
  Widget build(BuildContext context) {
    return InheritedGalleryBoundaries(state: this, child: widget.child);
  }
}

class InheritedGalleryBoundaries extends InheritedWidget {
  final GalleryBoundariesProviderState state;

  const InheritedGalleryBoundaries({
    super.key,
    required this.state,
    required super.child,
  });

  ValueNotifier<double?> get topBoundaryNotifier => state.topBoundaryNotifier;

  ValueNotifier<double?> get bottomBoundaryNotifier =>
      state.bottomBoundaryNotifier;

  ValueNotifier<ScrollController?> get scrollControllerNotifier =>
      state.scrollControllerNotifier;

  void setScrollController(ScrollController? controller) {
    state.setScrollController(controller);
  }

  void setTopBoundary(double? boundary) {
    state.setTopBoundary(boundary);
  }

  void setBottomBoundary(double? boundary) {
    state.setBottomBoundary(boundary);
  }

  @override
  bool updateShouldNotify(InheritedGalleryBoundaries oldWidget) {
    return false;
  }
}
