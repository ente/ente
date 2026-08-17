import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import "package:logging/logging.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_swipe_helper.dart';
import 'package:photos/ui/viewer/gallery/swipe_to_select_helper.dart';

class SwipeSelectionWrapper extends StatefulWidget {
  final Widget child;
  final SwipeToSelectHelper? swipeHelper;
  final SelectedFiles? selectedFiles;
  final bool isEnabled;
  final ValueNotifier<bool> swipeActiveNotifier;
  final ScrollController scrollController;

  const SwipeSelectionWrapper({
    super.key,
    required this.child,
    required this.swipeHelper,
    required this.selectedFiles,
    required this.isEnabled,
    required this.swipeActiveNotifier,
    required this.scrollController,
  });

  @override
  State<SwipeSelectionWrapper> createState() => _SwipeSelectionWrapperState();
}

class _SwipeSelectionWrapperState extends State<SwipeSelectionWrapper>
    with TickerProviderStateMixin {
  bool? _initialMovementWasHorizontal;
  bool _pointerDownForFirstSelection = false;
  final _logger = Logger('SwipeSelectionWrapper');

  Ticker? _autoScrollTicker;
  double _currentPointerY = 0;
  double _currentPointerX = 0;
  int? _activePointer;
  double? _cachedScreenHeight;
  double _accumulatedScrollDelta = 0;

  int? _currentScrollDirection;
  double _currentScrollSpeed = 0;
  ScrollController? _activeScrollController;
  Duration _lastElapsed = Duration.zero;

  late double _maxScrollSpeed;

  static const double _syntheticEventThreshold = 10.0;
  static const double _minAvailableSpace = 30.0;
  static const double _baselineRefreshRate = 120.0;
  static const double _baselineMaxScrollSpeed = 12.0; // px/frame at 120 Hz
  static const double _speedExponent = 1.20;
  static const double _movementThreshold = 4.0;

  @override
  void initState() {
    super.initState();
    _initializeFrameRateConstants();
  }

  void _initializeFrameRateConstants() {
    _maxScrollSpeed = _baselineMaxScrollSpeed * _baselineRefreshRate;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newHeight = MediaQuery.of(context).size.height;
    if (_cachedScreenHeight != newHeight) {
      _cachedScreenHeight = newHeight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boundariesProvider = GalleryBoundariesProvider.of(context);
    if (!widget.isEnabled) {
      return widget.child;
    }

    return GallerySwipeHelper(
      helper: widget.swipeHelper,
      swipeActiveNotifier: widget.swipeActiveNotifier,
      child: Listener(
        onPointerDown: (event) {
          _currentPointerX = event.position.dx;
          _currentPointerY = event.position.dy;
          _activePointer = event.pointer;
          _initialMovementWasHorizontal = null;
          _pointerDownForFirstSelection =
              widget.selectedFiles?.files.isEmpty ?? false;
        },
        onPointerMove: (event) {
          _currentPointerX = event.position.dx;
          _currentPointerY = event.position.dy;
          _activePointer = event.pointer;
          // A long press selects the first file before its drag starts.
          if (widget.selectedFiles != null &&
              widget.selectedFiles!.files.length == 1 &&
              !widget.swipeActiveNotifier.value &&
              _pointerDownForFirstSelection) {
            final dx = event.delta.dx.abs();
            final dy = event.delta.dy.abs();
            if (dx > _movementThreshold || dy > _movementThreshold) {
              widget.swipeActiveNotifier.value = true;
            }
          }
          // Existing selections start swipe mode only from horizontal movement.
          else if (!widget.swipeActiveNotifier.value &&
              widget.selectedFiles != null &&
              widget.selectedFiles!.files.isNotEmpty) {
            final dx = event.delta.dx.abs();
            final dy = event.delta.dy.abs();

            if (_initialMovementWasHorizontal == null &&
                (dx > _movementThreshold || dy > _movementThreshold)) {
              _initialMovementWasHorizontal = dx > dy;
            }

            if (_initialMovementWasHorizontal == true && dx > dy && dx > 0.1) {
              widget.swipeActiveNotifier.value = true;
            }
          }

          if (widget.swipeActiveNotifier.value) {
            _checkAndHandleAutoScroll(boundariesProvider);
          }
        },
        onPointerUp: (_) {
          _stopAutoScroll();
          widget.swipeHelper?.endSelection();
          widget.swipeActiveNotifier.value = false;
          _initialMovementWasHorizontal = null;
          _activePointer = null;
        },
        onPointerCancel: (_) {
          _stopAutoScroll();
          widget.swipeHelper?.endSelection();
          widget.swipeActiveNotifier.value = false;
          _initialMovementWasHorizontal = null;
          _activePointer = null;
        },
        child: widget.child,
      ),
    );
  }

  double _calculateScrollSpeed(
    double distanceFromBoundary,
    double boundaryPosition,
    bool scrollingUp,
  ) {
    if (distanceFromBoundary <= 0) return 0;

    final screenHeight =
        _cachedScreenHeight ?? MediaQuery.of(context).size.height;

    final widgetHeight = scrollingUp
        ? boundaryPosition
        : (screenHeight - boundaryPosition);

    final safeWidgetHeight = math.max(
      _minAvailableSpace,
      math.min(150.0, widgetHeight),
    );

    final penetration = math.min(1.0, distanceFromBoundary / safeWidgetHeight);

    final speed = _maxScrollSpeed * math.pow(penetration, _speedExponent);

    return speed;
  }

  void _checkAndHandleAutoScroll(InheritedGalleryBoundaries? provider) {
    if (provider == null) return;

    final topBoundary = provider.topBoundaryNotifier.value;
    final bottomBoundary = provider.bottomBoundaryNotifier.value;
    final scrollController = provider.scrollControllerNotifier.value;

    if (scrollController == null || !scrollController.hasClients) return;

    if (topBoundary != null &&
        bottomBoundary != null &&
        topBoundary >= bottomBoundary) {
      _stopAutoScroll();
      _logger.severe(
        'Invalid boundaries: top boundary ($topBoundary) >= bottom boundary ($bottomBoundary). '
        'Viewport is too small for auto-scroll.',
      );
      return;
    }

    if (topBoundary != null && _currentPointerY < topBoundary) {
      final distance = topBoundary - _currentPointerY;
      _startAutoScroll(scrollController, -1, distance, topBoundary, true);
    } else if (bottomBoundary != null && _currentPointerY > bottomBoundary) {
      final distance = _currentPointerY - bottomBoundary;
      _startAutoScroll(scrollController, 1, distance, bottomBoundary, false);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(
    ScrollController controller,
    int direction,
    double distance,
    double boundaryPosition,
    bool scrollingUp,
  ) {
    final scrollSpeed = _calculateScrollSpeed(
      distance,
      boundaryPosition,
      scrollingUp,
    );

    if (_autoScrollTicker != null &&
        _currentScrollDirection == direction &&
        _activeScrollController == controller) {
      _currentScrollSpeed = scrollSpeed;
      return;
    }

    _stopAutoScroll();
    _currentScrollDirection = direction;
    _currentScrollSpeed = scrollSpeed;
    _activeScrollController = controller;
    _lastElapsed = Duration.zero;

    _autoScrollTicker = createTicker((elapsed) {
      if (!mounted || !controller.hasClients) {
        _stopAutoScroll();
        return;
      }

      final deltaTime = elapsed - _lastElapsed;
      _lastElapsed = elapsed;

      final deltaSeconds = deltaTime.inMicroseconds / 1000000.0;

      final scrollDelta =
          _currentScrollSpeed * _currentScrollDirection! * deltaSeconds;

      final currentOffset = controller.offset;
      final newOffset = currentOffset + scrollDelta;

      final clampedOffset = newOffset.clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );

      if (clampedOffset != currentOffset) {
        final actualScrollDelta = (clampedOffset - currentOffset).abs();
        controller.jumpTo(clampedOffset);

        _accumulatedScrollDelta += actualScrollDelta;

        // Scrolling does not move the pointer, so dispatch a move to extend
        // selection.
        if (_accumulatedScrollDelta >= _syntheticEventThreshold &&
            widget.swipeActiveNotifier.value &&
            _activePointer != null) {
          final syntheticEvent = PointerMoveEvent(
            position: Offset(_currentPointerX, _currentPointerY),
            pointer: _activePointer!,
            timeStamp: elapsed,
          );
          GestureBinding.instance.handlePointerEvent(syntheticEvent);
          _accumulatedScrollDelta = 0;
        }
      }
    });

    _autoScrollTicker!.start();
  }

  void _stopAutoScroll() {
    _autoScrollTicker?.dispose();
    _autoScrollTicker = null;
    _accumulatedScrollDelta = 0;
    _currentScrollDirection = null;
    _currentScrollSpeed = 0;
    _activeScrollController = null;
    _lastElapsed = Duration.zero;
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }
}
