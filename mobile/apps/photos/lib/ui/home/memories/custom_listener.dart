import 'dart:async';
import 'package:flutter/widgets.dart';

class ActivePointers with ChangeNotifier {
  final Set<int> _activePointers = {};
  bool get hasActivePointers => _activePointers.isNotEmpty;
  bool activePointerWasPartOfMultitouch = false;

  void add(int pointer) {
    if (_activePointers.isNotEmpty && !_activePointers.contains(pointer)) {
      activePointerWasPartOfMultitouch = true;
    }
    _activePointers.add(pointer);
    notifyListeners();
  }

  void remove(int pointer) {
    _activePointers.remove(pointer);
    if (_activePointers.isEmpty) {
      activePointerWasPartOfMultitouch = false;
    }
    notifyListeners();
  }
}

/// `onLongPress` and `onLongPressUp` have not been tested enough to make sure
/// it works as expected, so they are commented out for now.
class MemoriesPointerGestureListener extends StatefulWidget {
  final Widget child;
  final Function(PointerEvent)? onTap;
  final VoidCallback? onSwipeUp;
  final bool Function()? canSwipeUp;
  // final VoidCallback? onLongPress;
  // final VoidCallback? onLongPressUp;

  /// How long the pointer must stay down before a long‐press fires.
  final Duration longPressDuration;

  /// Maximum movement (in logical pixels) before we consider it a drag.
  final double touchSlop;

  /// Minimum upward displacement before a gesture opens file details.
  final double swipeUpThreshold;

  /// Notifier that indicates whether there are active pointers.
  final ValueNotifier<bool>? hasPointerNotifier;
  static const double kTouchSlop = 18.0; // Default touch slop value

  const MemoriesPointerGestureListener({
    super.key,
    required this.child,
    this.onTap,
    this.onSwipeUp,
    this.canSwipeUp,
    // this.onLongPress,
    // this.onLongPressUp,
    this.hasPointerNotifier,
    this.longPressDuration = const Duration(milliseconds: 500),
    this.touchSlop = kTouchSlop, // from flutter/gestures/constants.dart
    this.swipeUpThreshold = 48,
  });

  @override
  MemoriesPointerGestureListenerState createState() =>
      MemoriesPointerGestureListenerState();
}

class MemoriesPointerGestureListenerState
    extends State<MemoriesPointerGestureListener> {
  Timer? _longPressTimer;
  bool _longPressFired = false;
  Offset? _downPosition;
  int? _trackedPointer;
  bool hasPointerMoved = false;
  final _activePointers = ActivePointers();

  @override
  void initState() {
    super.initState();
    _activePointers.addListener(_activatePointerListener);
  }

  void _activatePointerListener() {
    if (widget.hasPointerNotifier != null) {
      widget.hasPointerNotifier!.value = _activePointers.hasActivePointers;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _addPointer(event.pointer);
    if (_trackedPointer != null) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      return;
    }
    _trackedPointer = event.pointer;
    _downPosition = event.localPosition;
    _longPressFired = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(widget.longPressDuration, () {
      _longPressFired = true;
      // widget.onLongPress?.call();
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer == _trackedPointer && _downPosition != null) {
      final distance = (event.localPosition - _downPosition!).distance;
      if (distance > widget.touchSlop) {
        // user started dragging – cancel long‐press
        hasPointerMoved = true;
        _longPressTimer?.cancel();
        _longPressTimer = null;
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _trackedPointer) {
      _removePointer(event.pointer);
      return;
    }

    _longPressTimer?.cancel();
    _longPressTimer = null;
    final wasPartOfMultitouch =
        _activePointers.activePointerWasPartOfMultitouch;
    final displacement = event.localPosition - _downPosition!;
    final isSwipeUp =
        widget.onSwipeUp != null &&
        (widget.canSwipeUp?.call() ?? true) &&
        !wasPartOfMultitouch &&
        displacement.dy <= -widget.swipeUpThreshold &&
        displacement.dy.abs() > displacement.dx.abs() &&
        displacement.dx.abs() <= widget.touchSlop;

    // Release the pointer before callbacks so opening a sheet can take over
    // the viewer's pause state without the release immediately resuming it.
    _removePointer(event.pointer);

    if (isSwipeUp) {
      widget.onSwipeUp?.call();
    } else if (_longPressFired) {
      // widget.onLongPressUp?.call();
    } else {
      if (!wasPartOfMultitouch && !hasPointerMoved) {
        widget.onTap?.call(event);
      }
    }
    _reset();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _trackedPointer) {
      _removePointer(event.pointer);
      return;
    }
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressFired = false;
    _removePointer(event.pointer);
    _reset();
  }

  void _removePointer(int pointer) {
    _activePointers.remove(pointer);
  }

  void _addPointer(int pointer) {
    _activePointers.add(pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _activePointers.removeListener(_activatePointerListener);
    _activePointers.dispose();
    super.dispose();
  }

  void _reset() {
    hasPointerMoved = false;
    _downPosition = null;
    _trackedPointer = null;
  }
}
