import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart';

enum BoundaryPosition { top, bottom }

/// Mixin for widgets that act as boundaries for auto-scroll
/// Reports their position to GalleryBoundariesProvider with debouncing
mixin BoundaryReporter<T extends StatefulWidget> on State<T> {
  final _boundaryKey = GlobalKey();
  Timer? _boundaryUpdateTimer;

  /// Report this widget's boundary to the provider
  /// Call this when the widget is first built and when its size or position changes.
  /// Note: If using boundaryWidget() wrapper, boundaries are reported automatically
  /// after each build - manual calls are only needed for dynamic updates (e.g., visibility changes).
  void reportBoundary(BoundaryPosition position) {
    // Debounce updates to avoid excessive recalculation
    _boundaryUpdateTimer?.cancel();
    _boundaryUpdateTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      final provider = GalleryBoundariesProvider.of(context);
      assert(
        provider != null,
        'GalleryBoundariesProvider not found in context. '
        'Ensure BoundaryReporter is used within a GalleryBoundariesProvider.',
      );
      if (provider == null) return;

      final renderBox =
          _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final offset = renderBox.localToGlobal(Offset.zero);
        final boundary = position == BoundaryPosition.top
            ? offset.dy +
                  renderBox
                      .size
                      .height // Bottom edge of top widget
            : offset.dy; // Top edge of bottom widget

        if (position == BoundaryPosition.top) {
          provider.setTopBoundary(boundary);
        } else {
          provider.setBottomBoundary(boundary);
        }
      } else {
        // RenderBox not available (widget hidden/removed) - clear boundary
        if (position == BoundaryPosition.top) {
          provider.setTopBoundary(null);
        } else {
          provider.setBottomBoundary(null);
        }
      }
    });
  }

  /// Widget that should have its boundary tracked
  /// Wrap your widget content with this
  Widget boundaryWidget({
    required Widget child,
    required BoundaryPosition position,
  }) {
    // Report boundary after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reportBoundary(position);
    });

    return Container(key: _boundaryKey, child: child);
  }

  @override
  void dispose() {
    _boundaryUpdateTimer?.cancel();
    super.dispose();
  }
}
