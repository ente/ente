import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import "package:photos/models/gallery/fixed_extent_section_layout.dart";

// Based on code from https://github.com/deckerst/aves
// Copyright (c) 2020-2023 Thibault Deckers and contributors
// Licensed under BSD-3-Clause License

// Using a Single SliverVariedExtentList or Using a combination where there are
// multiple sliver delegate builders in a CustomScrollView doesn't scale.

// With using a Single SliverKnownExtentList with each section being either a
// group header or a row of grid, the problem is that scrolling becomes janky
// the deeper the list is scrolled if the list is large enough.

// With using multiple slivers (and hence multiple SliverChildBuilderDelegates)
// in CustomScrollView, the deep scrolling issue exists and the first child
// of every builderDelegate is always initialized, even if it's not in viewport
// or in cacheExtent.

// https://github.com/flutter/flutter/issues/168442
// https://github.com/flutter/flutter/issues/95028

// A custom implementation of SliverMultiBoxAdaptorWidget
// adapted from SliverFixedExtentBoxAdaptor. Optimizations in layout solves
// the deep scrolling issue.

class SectionedListSliver<T> extends StatelessWidget {
  final List<FixedExtentSectionLayout> sectionLayouts;
  const SectionedListSliver({super.key, required this.sectionLayouts});

  @override
  Widget build(BuildContext context) {
    final childCount = sectionLayouts.isEmpty
        ? 0
        : sectionLayouts.last.lastIndex + 1;
    return _SliverKnownExtentList(
      sectionLayouts: sectionLayouts,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= childCount) return null;
          final sectionLayout = sectionLayouts.firstWhereOrNull(
            (section) => section.hasChild(index),
          );
          return sectionLayout?.builder(context, index) ?? const SizedBox();
        },
        childCount: childCount,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
      ),
    );
  }
}

class _SliverKnownExtentList extends SliverMultiBoxAdaptorWidget {
  final List<FixedExtentSectionLayout> sectionLayouts;

  const _SliverKnownExtentList({
    required super.delegate,
    required this.sectionLayouts,
  });

  @override
  _RenderSliverKnownExtentBoxAdaptor createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return _RenderSliverKnownExtentBoxAdaptor(
      childManager: element,
      sectionLayouts: sectionLayouts,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverKnownExtentBoxAdaptor renderObject,
  ) {
    renderObject.sectionLayouts = sectionLayouts;
  }
}

class _RenderSliverKnownExtentBoxAdaptor extends RenderSliverMultiBoxAdaptor {
  List<FixedExtentSectionLayout> _sectionLayouts;

  List<FixedExtentSectionLayout> get sectionLayouts => _sectionLayouts;

  set sectionLayouts(List<FixedExtentSectionLayout> value) {
    if (_sectionLayouts == value) return;
    _sectionLayouts = value;
    markNeedsLayout();
  }

  _RenderSliverKnownExtentBoxAdaptor({
    required super.childManager,
    required List<FixedExtentSectionLayout> sectionLayouts,
  }) : _sectionLayouts = sectionLayouts;

  FixedExtentSectionLayout? sectionAtIndex(int index) =>
      sectionLayouts.firstWhereOrNull((section) => section.hasChild(index));

  FixedExtentSectionLayout? sectionAtOffset(double scrollOffset) =>
      sectionLayouts.firstWhereOrNull(
        (section) => section.hasChildAtOffset(scrollOffset),
      ) ??
      sectionLayouts.lastOrNull;

  double indexToLayoutOffset(int index) {
    return (sectionAtIndex(index) ?? sectionLayouts.lastOrNull)
            ?.indexToLayoutOffset(index) ??
        0;
  }

  int getMinChildIndexForScrollOffset(double scrollOffset) {
    return sectionAtOffset(
          scrollOffset,
        )?.getMinChildIndexForScrollOffset(scrollOffset) ??
        0;
  }

  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    return sectionAtOffset(
          scrollOffset,
        )?.getMaxChildIndexForScrollOffset(scrollOffset) ??
        0;
  }

  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    // default implementation is an estimation via `childManager.estimateMaxScrollOffset()`
    // but we have the accurate offset via pre-computed section layouts
    return _sectionLayouts.last.maxOffset;
  }

  double computeMaxScrollOffset(SliverConstraints constraints) {
    return sectionLayouts.last.maxOffset;
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final scrollOffset = constraints.scrollOffset + constraints.cacheOrigin;
    assert(scrollOffset >= 0.0);
    final remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final targetEndScrollOffset = scrollOffset + remainingExtent;

    // TODO: Potential improvement: Instead of using same contraints for all children,
    // use a helper method that returns constrains for an index. So it should
    // return the itemExtent of that index.
    final childConstraints = constraints.asBoxConstraints();

    final firstIndex = getMinChildIndexForScrollOffset(scrollOffset);
    final targetLastIndex = targetEndScrollOffset.isFinite
        ? getMaxChildIndexForScrollOffset(targetEndScrollOffset)
        : null;

    if (firstChild != null) {
      final leadingGarbage = calculateLeadingGarbage(firstIndex: firstIndex);
      final trailingGarbage = targetLastIndex != null
          ? calculateTrailingGarbage(lastIndex: targetLastIndex)
          : 0;
      collectGarbage(leadingGarbage, trailingGarbage);
    } else {
      collectGarbage(0, 0);
    }

    if (firstChild == null) {
      if (!addInitialChild(
        index: firstIndex,
        layoutOffset: indexToLayoutOffset(firstIndex),
      )) {
        // There are either no children, or we are past the end of all our children.
        double max;
        if (firstIndex <= 0) {
          max = 0.0;
        } else {
          max = computeMaxScrollOffset(constraints);
        }
        geometry = SliverGeometry(scrollExtent: max, maxPaintExtent: max);
        childManager.didFinishLayout();
        return;
      }
    }

    RenderBox? trailingChildWithLayout;

    for (var index = indexOf(firstChild!) - 1; index >= firstIndex; --index) {
      final child = insertAndLayoutLeadingChild(childConstraints);
      if (child == null) {
        // Items before the previously first child are no longer present.
        // Reset the scroll offset to offset all items prior and up to the
        // missing item. Let parent re-layout everything.
        final layout = sectionAtIndex(index) ?? sectionLayouts.first;
        geometry = SliverGeometry(
          scrollOffsetCorrection: layout.indexToLayoutOffset(index),
        );
        return;
      }
      final childParentData =
          child.parentData as SliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset = indexToLayoutOffset(index);
      assert(childParentData.index == index);
      trailingChildWithLayout ??= child;
    }

    if (trailingChildWithLayout == null) {
      firstChild!.layout(childConstraints);
      final childParentData =
          firstChild!.parentData as SliverMultiBoxAdaptorParentData;
      childParentData.layoutOffset = indexToLayoutOffset(firstIndex);
      trailingChildWithLayout = firstChild;
    }

    var estimatedMaxScrollOffset = double.infinity;
    for (
      var index = indexOf(trailingChildWithLayout!) + 1;
      targetLastIndex == null || index <= targetLastIndex;
      ++index
    ) {
      var child = childAfter(trailingChildWithLayout!);
      if (child == null || indexOf(child) != index) {
        child = insertAndLayoutChild(
          childConstraints,
          after: trailingChildWithLayout,
        );
        if (child == null) {
          // We have run out of children.
          final layout = sectionAtIndex(index) ?? sectionLayouts.last;
          estimatedMaxScrollOffset = layout.maxOffset;
          break;
        }
      } else {
        child.layout(childConstraints);
      }
      trailingChildWithLayout = child;
      final childParentData =
          child.parentData as SliverMultiBoxAdaptorParentData;
      assert(childParentData.index == index);
      childParentData.layoutOffset = indexToLayoutOffset(
        childParentData.index!,
      );
    }

    final lastIndex = indexOf(lastChild!);
    final leadingScrollOffset = indexToLayoutOffset(firstIndex);
    final trailingScrollOffset = indexToLayoutOffset(lastIndex + 1);

    assert(
      firstIndex == 0 ||
          childScrollOffset(firstChild!)! - scrollOffset <=
              precisionErrorTolerance,
    );
    assert(debugAssertChildListIsNonEmptyAndContiguous());
    assert(indexOf(firstChild!) == firstIndex);
    assert(targetLastIndex == null || lastIndex <= targetLastIndex);

    estimatedMaxScrollOffset = math.min(
      estimatedMaxScrollOffset,
      estimateMaxScrollOffset(
        constraints,
        firstIndex: firstIndex,
        lastIndex: lastIndex,
        leadingScrollOffset: leadingScrollOffset,
        trailingScrollOffset: trailingScrollOffset,
      ),
    );

    final paintExtent = calculatePaintOffset(
      constraints,
      from: math.min(constraints.scrollOffset, leadingScrollOffset),
      to: trailingScrollOffset,
    );

    final cacheExtent = calculateCacheOffset(
      constraints,
      from: leadingScrollOffset,
      to: trailingScrollOffset,
    );

    final targetEndScrollOffsetForPaint =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    final targetLastIndexForPaint = targetEndScrollOffsetForPaint.isFinite
        ? getMaxChildIndexForScrollOffset(targetEndScrollOffsetForPaint)
        : null;
    geometry = SliverGeometry(
      scrollExtent: estimatedMaxScrollOffset,
      paintExtent: math.min(paintExtent, estimatedMaxScrollOffset),
      cacheExtent: cacheExtent,
      maxPaintExtent: estimatedMaxScrollOffset,
      // Conservative to avoid flickering away the clip during scroll.
      hasVisualOverflow:
          (targetLastIndexForPaint != null &&
              lastIndex >= targetLastIndexForPaint) ||
          constraints.scrollOffset > 0.0,
    );

    // We may have started the layout while scrolled to the end, which would not
    // expose a new child.
    if (estimatedMaxScrollOffset == trailingScrollOffset) {
      childManager.setDidUnderflow(true);
    }
    childManager.didFinishLayout();
  }
}
