import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart';

enum BoundaryPosition { top, bottom }

mixin BoundaryReporter<T extends StatefulWidget> on State<T> {
  final _boundaryKey = GlobalKey();
  Timer? _boundaryUpdateTimer;

  void reportBoundary(BoundaryPosition position) {
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
            ? offset.dy + renderBox.size.height
            : offset.dy;

        if (position == BoundaryPosition.top) {
          provider.setTopBoundary(boundary);
        } else {
          provider.setBottomBoundary(boundary);
        }
      } else {
        if (position == BoundaryPosition.top) {
          provider.setTopBoundary(null);
        } else {
          provider.setBottomBoundary(null);
        }
      }
    });
  }

  Widget boundaryWidget({
    required Widget child,
    required BoundaryPosition position,
  }) {
    // Report after layout so the RenderBox has a position.
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
