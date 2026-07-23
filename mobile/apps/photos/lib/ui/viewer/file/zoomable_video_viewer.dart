import "package:flutter/widgets.dart";

/// Threshold for considering the view as "zoomed in".
/// Using 1.01 instead of 1.0 to account for floating-point precision.
const double kZoomThreshold = 1.01;

/// A widget that wraps [InteractiveViewer] with multi-touch detection.
///
/// This widget solves a gesture arena race condition: when pinch-to-zoom
/// is attempted on a video inside a PageView, the PageView's drag gesture
/// recognizer can claim single-finger touches before InteractiveViewer's
/// scale gesture recognizer detects the second finger.
///
/// By using a low-level [Listener], we detect multi-touch at the pointer
/// level (before gesture arena processing) and immediately disable the
/// parent PageView's scrolling.
class ZoomableVideoViewer extends StatefulWidget {
  final TransformationController transformationController;
  final ValueChanged<bool>? onInteractionLockChanged;
  final Widget child;

  const ZoomableVideoViewer({
    super.key,
    required this.transformationController,
    this.onInteractionLockChanged,
    required this.child,
  });

  @override
  State<ZoomableVideoViewer> createState() => _ZoomableVideoViewerState();
}

class _ZoomableVideoViewerState extends State<ZoomableVideoViewer> {
  int _activePointers = 0;
  bool _isInteractionLocked = false;

  @override
  void initState() {
    super.initState();
    widget.transformationController.addListener(_onTransformationChanged);
    _updateInteractionLockState();
  }

  @override
  void didUpdateWidget(covariant ZoomableVideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformationController != widget.transformationController) {
      oldWidget.transformationController.removeListener(
        _onTransformationChanged,
      );
      widget.transformationController.addListener(_onTransformationChanged);
      _updateInteractionLockState();
    }
  }

  @override
  void dispose() {
    widget.transformationController.removeListener(_onTransformationChanged);
    super.dispose();
  }

  void _onTransformationChanged() {
    _updateInteractionLockState();
  }

  void _onPointerDown(PointerDownEvent _) {
    _activePointers++;
    _updateInteractionLockState();
  }

  void _onPointerUp(PointerUpEvent _) {
    _activePointers = (_activePointers - 1).clamp(0, 99);
    _updateInteractionLockState();
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _activePointers = (_activePointers - 1).clamp(0, 99);
    _updateInteractionLockState();
  }

  void _updateInteractionLockState() {
    final scale = widget.transformationController.value.getMaxScaleOnAxis();
    final shouldLock = _activePointers >= 2 || scale > kZoomThreshold;
    if (_isInteractionLocked == shouldLock) {
      return;
    }
    _isInteractionLocked = shouldLock;
    widget.onInteractionLockChanged?.call(shouldLock);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: InteractiveViewer(
        transformationController: widget.transformationController,
        maxScale: 10.0,
        minScale: 1.0,
        child: widget.child,
      ),
    );
  }
}
