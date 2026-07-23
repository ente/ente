import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import "package:logging/logging.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart';
import 'package:photos/ui/viewer/gallery/state/gallery_swipe_helper.dart';
import 'package:photos/ui/viewer/gallery/swipe_to_select_helper.dart';

/// A wrapper widget that handles swipe-to-select gesture detection and state management
/// for the Gallery widget.
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

  // Auto-scroll related fields
  Ticker? _autoScrollTicker;
  double _currentPointerY = 0;
  double _currentPointerX = 0;
  int? _activePointer;
  double? _cachedScreenHeight;
  double _accumulatedScrollDelta = 0;

  // Auto-scroll state tracking to avoid ticker recreation
  int? _currentScrollDirection; // -1 for up, 1 for down, null for not scrolling
  double _currentScrollSpeed = 0;
  ScrollController? _activeScrollController;
  Duration _lastElapsed = Duration.zero;

  // Frame rate adaptive fields
  late double _maxScrollSpeed; // Max scroll speed in pixels per second

  // Auto-scroll constants
  static const double _syntheticEventThreshold =
      10.0; // Pixels before generating event
  static const double _minAvailableSpace =
      30.0; // Minimum widget height for safety
  static const double _baselineRefreshRate = 120.0;
  static const double _baselineMaxScrollSpeed = 12.0; // 1440 px/s (12 * 120fps)
  static const double _speedExponent = 1.20; // Power curve exponent
  static const double _movementThreshold = 4.0;

  @override
  void initState() {
    super.initState();
    _initializeFrameRateConstants();
  }

  void _initializeFrameRateConstants() {
    // Convert baseline speed from "px/frame at 120fps" to "px/second"
    // This ensures consistent visual speed across all refresh rates
    // E.g., baseline 10 px/frame at 120fps = 1200 px/second
    // All devices (60fps, 90fps, 120fps) will scroll at this same visual speed
    _maxScrollSpeed = _baselineMaxScrollSpeed * _baselineRefreshRate;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update cached screen height when dependencies change (includes orientation changes)
    final newHeight = MediaQuery.of(context).size.height;
    if (_cachedScreenHeight != newHeight) {
      _cachedScreenHeight = newHeight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boundariesProvider = GalleryBoundariesProvider.of(context);
    // If swipe selection is not enabled, just return the child without wrapper
    if (!widget.isEnabled) {
      return widget.child;
    }

    // Wrap with GallerySwipeHelper and Listener for swipe detection
    return GallerySwipeHelper(
      helper: widget.swipeHelper,
      swipeActiveNotifier: widget.swipeActiveNotifier,
      child: Listener(
        onPointerDown: (event) {
          _currentPointerX = event.position.dx;
          _currentPointerY = event.position.dy;
          _activePointer = event.pointer;
          // Reset initial movement tracking for new gesture
          _initialMovementWasHorizontal = null;
          // Track if pointer down happened when no files were selected
          // This indicates it's the initial selection gesture (long-press)
          _pointerDownForFirstSelection =
              widget.selectedFiles?.files.isEmpty ?? false;
        },
        onPointerMove: (event) {
          _currentPointerX = event.position.dx;
          _currentPointerY = event.position.dy;
          _activePointer = event.pointer;
          // Handle case where pointer is dragged after first selection in gallery
          if (widget.selectedFiles != null &&
              widget.selectedFiles!.files.length == 1 &&
              !widget.swipeActiveNotifier.value &&
              _pointerDownForFirstSelection) {
            // Activate swipe mode for any significant movement when only one file is selected
            // This handles the case of long-press to select first file, then immediate swipe
            // including vertical movement without initial horizontal movement
            // Only applies if pointer down was for the initial selection (continuous gesture)
            final dx = event.delta.dx.abs();
            final dy = event.delta.dy.abs();
            if (dx > _movementThreshold || dy > _movementThreshold) {
              widget.swipeActiveNotifier.value = true;
            }
          }
          // Check for horizontal swipe if multiple files are selected and swipe is not already active
          else if (!widget.swipeActiveNotifier.value &&
              widget.selectedFiles != null &&
              widget.selectedFiles!.files.isNotEmpty) {
            // Check if movement is primarily horizontal and if delta x is significant
            final dx = event.delta.dx.abs();
            final dy = event.delta.dy.abs();

            // Track initial movement direction if not yet determined
            if (_initialMovementWasHorizontal == null &&
                (dx > _movementThreshold || dy > _movementThreshold)) {
              _initialMovementWasHorizontal = dx > dy;
            }

            // Only activate swipe if initial movement was horizontal
            if (_initialMovementWasHorizontal == true && dx > dy && dx > 0.1) {
              // Horizontal swipe detected, activate swipe mode
              widget.swipeActiveNotifier.value = true;
            }
          }

          // Check for auto-scroll if swipe is active
          if (widget.swipeActiveNotifier.value) {
            _checkAndHandleAutoScroll(boundariesProvider);
          }
        },
        onPointerUp: (_) {
          _stopAutoScroll();
          // End swipe selection when pointer is released
          widget.swipeHelper?.endSelection();
          widget.swipeActiveNotifier.value = false;
          _initialMovementWasHorizontal = null;
          _activePointer = null;
        },
        onPointerCancel: (_) {
          _stopAutoScroll();
          // Also end selection on cancel
          widget.swipeHelper?.endSelection();
          widget.swipeActiveNotifier.value = false;
          _initialMovementWasHorizontal = null;
          _activePointer = null;
        },
        child: widget.child,
      ),
    );
  }

  /// Calculate scroll speed based on widget penetration percentage with power curve
  double _calculateScrollSpeed(
    double distanceFromBoundary,
    double boundaryPosition,
    bool scrollingUp,
  ) {
    if (distanceFromBoundary <= 0) return 0;

    final screenHeight =
        _cachedScreenHeight ?? MediaQuery.of(context).size.height;

    // Calculate available space (widget height) from boundary to screen edge
    final widgetHeight = scrollingUp
        ? boundaryPosition // Space from top boundary to screen top
        : (screenHeight -
              boundaryPosition); // Space from bottom boundary to screen bottom

    // Apply safety floor and cap at 150px
    // Small widgets (< 150px): Speed ramps up over their full height
    // Large widgets (>= 150px): Speed maxes out at 150px from boundary
    final safeWidgetHeight = math.max(
      _minAvailableSpace,
      math.min(150.0, widgetHeight),
    );

    // Calculate penetration percentage (0.0 to 1.0)
    // Clamped to 1.0 to handle cases where pointer goes beyond widget bounds
    final penetration = math.min(1.0, distanceFromBoundary / safeWidgetHeight);

    // Apply power curve for slightly exponential feel
    // speed = maxSpeed × (penetration ^ exponent)
    final speed = _maxScrollSpeed * math.pow(penetration, _speedExponent);

    return speed;
  }

  /// Check if pointer is inside/outside boundaries and start/stop auto-scroll
  void _checkAndHandleAutoScroll(InheritedGalleryBoundaries? provider) {
    if (provider == null) return;

    final topBoundary = provider.topBoundaryNotifier.value;
    final bottomBoundary = provider.bottomBoundaryNotifier.value;
    final scrollController = provider.scrollControllerNotifier.value;

    if (scrollController == null || !scrollController.hasClients) return;

    // Validate boundaries don't overlap (viewport too small)
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

    // Determine if we need to scroll and in which direction
    if (topBoundary != null && _currentPointerY < topBoundary) {
      // Pointer is above top boundary - scroll up
      final distance = topBoundary - _currentPointerY;
      _startAutoScroll(scrollController, -1, distance, topBoundary, true);
    } else if (bottomBoundary != null && _currentPointerY > bottomBoundary) {
      // Pointer is below bottom boundary - scroll down
      final distance = _currentPointerY - bottomBoundary;
      _startAutoScroll(scrollController, 1, distance, bottomBoundary, false);
    } else {
      // Pointer is within boundaries - stop scrolling
      _stopAutoScroll();
    }
  }

  /// Start auto-scrolling in the specified direction
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

    // Check if we're already scrolling in the same direction
    // If yes, just update the speed without recreating the ticker
    if (_autoScrollTicker != null &&
        _currentScrollDirection == direction &&
        _activeScrollController == controller) {
      // Just update the scroll speed, ticker continues running
      _currentScrollSpeed = scrollSpeed;
      return;
    }

    // Direction changed or starting fresh - recreate ticker
    _stopAutoScroll();
    _currentScrollDirection = direction;
    _currentScrollSpeed = scrollSpeed;
    _activeScrollController = controller;
    _lastElapsed = Duration.zero;

    // Create vsync-synchronized ticker for smooth scrolling
    _autoScrollTicker = createTicker((elapsed) {
      if (!mounted || !controller.hasClients) {
        _stopAutoScroll();
        return;
      }

      // Calculate delta time since last frame
      final deltaTime = elapsed - _lastElapsed;
      _lastElapsed = elapsed;

      // Calculate scroll distance for this frame using delta-time
      // Convert microseconds to seconds for calculation
      final deltaSeconds = deltaTime.inMicroseconds / 1000000.0;

      // Formula: pixels_per_second × direction × actual_frame_time_in_seconds
      // _currentScrollSpeed is in "pixels per second" (e.g., 4800 px/s for max speed)
      // Multiplying by deltaSeconds gives actual pixels to scroll this frame
      // Example at 60fps: 4800px/s × 0.0166s ≈ 80px per frame
      // Example at 120fps: 4800px/s × 0.00833s ≈ 40px per frame
      // Visual speed is the same: both scroll 4800 pixels per second
      final scrollDelta =
          _currentScrollSpeed * _currentScrollDirection! * deltaSeconds;

      // Calculate new scroll position
      final currentOffset = controller.offset;
      final newOffset = currentOffset + scrollDelta;

      // Clamp to scroll bounds
      final clampedOffset = newOffset.clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );

      // Use jumpTo for immediate positioning
      if (clampedOffset != currentOffset) {
        final actualScrollDelta = (clampedOffset - currentOffset).abs();
        controller.jumpTo(clampedOffset);

        // Accumulate scroll delta for synthetic event generation
        _accumulatedScrollDelta += actualScrollDelta;

        // Generate synthetic pointer event when threshold is reached
        if (_accumulatedScrollDelta >= _syntheticEventThreshold &&
            widget.swipeActiveNotifier.value &&
            _activePointer != null) {
          final syntheticEvent = PointerMoveEvent(
            position: Offset(_currentPointerX, _currentPointerY),
            pointer: _activePointer!,
            timeStamp: elapsed,
          );
          GestureBinding.instance.handlePointerEvent(syntheticEvent);
          // Reset accumulator after generating event
          _accumulatedScrollDelta = 0;
        }
      }
    });

    // Start the ticker
    _autoScrollTicker!.start();
  }

  /// Stop auto-scrolling
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
