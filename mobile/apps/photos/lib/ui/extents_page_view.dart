import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide PageView;

// Copied from Flutter commit 3932ffb1cd5dfa0c3891c60977ee4f9cd70ade66.
// This version uses Viewport.cacheExtent to build pages off screen.

const PageScrollPhysics _kPagePhysics = PageScrollPhysics();

class ExtentsPageView extends StatefulWidget {
  ExtentsPageView({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    required this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    List<Widget> children = const <Widget>[],
    this.dragStartBehavior = DragStartBehavior.start,
    this.openDrawer,
  }) : childrenDelegate = SliverChildListDelegate(children),
       extents = children.length;

  ExtentsPageView.builder({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    required this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required IndexedWidgetBuilder itemBuilder,
    int? itemCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.openDrawer,
  }) : childrenDelegate = SliverChildBuilderDelegate(
         itemBuilder,
         childCount: itemCount,
       ),
       extents = 0;

  ExtentsPageView.extents({
    super.key,
    this.extents = 1,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    required this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required IndexedWidgetBuilder itemBuilder,
    int? itemCount,
    this.dragStartBehavior = DragStartBehavior.start,
    this.openDrawer,
  }) : childrenDelegate = SliverChildBuilderDelegate(
         itemBuilder,
         childCount: itemCount,
         addAutomaticKeepAlives: false,
         addRepaintBoundaries: false,
       );

  const ExtentsPageView.custom({
    super.key,
    this.scrollDirection = Axis.horizontal,
    this.reverse = false,
    required this.controller,
    this.physics,
    this.pageSnapping = true,
    this.onPageChanged,
    required this.childrenDelegate,
    this.dragStartBehavior = DragStartBehavior.start,
    this.openDrawer,
  }) : extents = 0;

  final int extents;
  final Axis scrollDirection;
  final bool reverse;
  final PageController controller;
  final ScrollPhysics? physics;
  final bool pageSnapping;
  final ValueChanged<int>? onPageChanged;
  final SliverChildDelegate childrenDelegate;
  final DragStartBehavior dragStartBehavior;
  final Function? openDrawer;

  @override
  State<ExtentsPageView> createState() => _PageViewState();
}

class _PageViewState extends State<ExtentsPageView> {
  int _lastReportedPage = 0;
  VoidCallback? _openDrawerListener;

  @override
  void initState() {
    super.initState();
    _lastReportedPage = widget.controller.initialPage;
    if (widget.openDrawer != null) {
      _openDrawerListener = () {
        if (widget.controller.offset < -45) {
          widget.openDrawer!();
        }
      };
      widget.controller.addListener(_openDrawerListener!);
    }
  }

  @override
  void dispose() {
    if (_openDrawerListener != null) {
      widget.controller.removeListener(_openDrawerListener!);
    }
    super.dispose();
  }

  AxisDirection? _getDirection(BuildContext context) {
    switch (widget.scrollDirection) {
      case Axis.horizontal:
        assert(debugCheckHasDirectionality(context));
        final TextDirection textDirection = Directionality.of(context);
        final AxisDirection axisDirection = textDirectionToAxisDirection(
          textDirection,
        );
        return widget.reverse
            ? flipAxisDirection(axisDirection)
            : axisDirection;
      case Axis.vertical:
        return widget.reverse ? AxisDirection.up : AxisDirection.down;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AxisDirection axisDirection = _getDirection(context)!;
    final ScrollPhysics? physics = widget.pageSnapping
        ? _kPagePhysics.applyTo(widget.physics)
        : widget.physics;

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (notification.depth == 0 &&
            widget.onPageChanged != null &&
            notification is ScrollUpdateNotification) {
          final PageMetrics metrics = notification.metrics as PageMetrics;
          final int currentPage = metrics.page!.round();
          if (currentPage != _lastReportedPage) {
            _lastReportedPage = currentPage;
            widget.onPageChanged!(currentPage);
          }
        }
        return false;
      },
      child: Scrollable(
        dragStartBehavior: widget.dragStartBehavior,
        axisDirection: axisDirection,
        controller: widget.controller,
        physics: physics,
        viewportBuilder: (BuildContext context, ViewportOffset position) {
          return LayoutBuilder(
            builder: (context, constraints) {
              assert(constraints.hasBoundedHeight);
              assert(constraints.hasBoundedWidth);

              double cacheExtent;

              switch (widget.scrollDirection) {
                case Axis.vertical:
                  cacheExtent = constraints.maxHeight * widget.extents;
                  break;

                case Axis.horizontal:
                  cacheExtent = constraints.maxWidth * widget.extents;
                  break;
              }

              return Viewport(
                cacheExtent: cacheExtent,
                axisDirection: axisDirection,
                offset: position,
                slivers: <Widget>[
                  SliverFillViewport(
                    viewportFraction: widget.controller.viewportFraction,
                    delegate: widget.childrenDelegate,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(
      EnumProperty<Axis>('scrollDirection', widget.scrollDirection),
    );
    description.add(
      FlagProperty('reverse', value: widget.reverse, ifTrue: 'reversed'),
    );
    description.add(
      DiagnosticsProperty<PageController>(
        'controller',
        widget.controller,
        showName: false,
      ),
    );
    description.add(
      DiagnosticsProperty<ScrollPhysics>(
        'physics',
        widget.physics,
        showName: false,
      ),
    );
    description.add(
      FlagProperty(
        'pageSnapping',
        value: widget.pageSnapping,
        ifFalse: 'snapping disabled',
      ),
    );
  }
}
