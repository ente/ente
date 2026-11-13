import 'package:flutter/foundation.dart' show ValueListenable;
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

  late final ValueNotifier<double?> selectionSheetMinHeightNotifier;

  late final ValueNotifier<ScrollController?> scrollControllerNotifier;
  ValueListenable<bool>? swipeActiveNotifier;

  @override
  void initState() {
    super.initState();
    topBoundaryNotifier = ValueNotifier<double?>(null);
    bottomBoundaryNotifier = ValueNotifier<double?>(null);
    selectionSheetMinHeightNotifier = ValueNotifier<double?>(null);
    scrollControllerNotifier = ValueNotifier<ScrollController?>(null);
  }

  @override
  void dispose() {
    topBoundaryNotifier.dispose();
    bottomBoundaryNotifier.dispose();
    selectionSheetMinHeightNotifier.dispose();
    scrollControllerNotifier.dispose();
    super.dispose();
  }

  void setScrollController(
    ScrollController? controller, {
    ValueListenable<bool>? swipeActiveNotifier,
  }) {
    this.swipeActiveNotifier = swipeActiveNotifier;
    scrollControllerNotifier.value = controller;
  }

  void setTopBoundary(double? boundary) {
    topBoundaryNotifier.value = boundary;
  }

  void setBottomBoundary(double? boundary) {
    bottomBoundaryNotifier.value = boundary;
  }

  void setSelectionSheetMinHeight(double? height) {
    selectionSheetMinHeightNotifier.value = height;
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

  ValueNotifier<double?> get selectionSheetMinHeightNotifier =>
      state.selectionSheetMinHeightNotifier;

  ValueNotifier<ScrollController?> get scrollControllerNotifier =>
      state.scrollControllerNotifier;

  ValueListenable<bool>? get swipeActiveNotifier => state.swipeActiveNotifier;

  void setScrollController(
    ScrollController? controller, {
    ValueListenable<bool>? swipeActiveNotifier,
  }) {
    state.setScrollController(
      controller,
      swipeActiveNotifier: swipeActiveNotifier,
    );
  }

  void setTopBoundary(double? boundary) {
    state.setTopBoundary(boundary);
  }

  void setBottomBoundary(double? boundary) {
    state.setBottomBoundary(boundary);
  }

  void setSelectionSheetMinHeight(double? height) {
    state.setSelectionSheetMinHeight(height);
  }

  @override
  bool updateShouldNotify(InheritedGalleryBoundaries oldWidget) {
    return false;
  }
}
