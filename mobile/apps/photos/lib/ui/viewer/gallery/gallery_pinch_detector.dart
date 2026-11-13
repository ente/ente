import "package:flutter/gestures.dart";
import "package:flutter/widgets.dart";

class GalleryPinchDetector extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final ValueChanged<Offset> onStart;
  final void Function(double scale, Offset localFocalPoint) onUpdate;
  final ValueChanged<bool> onEnd;

  const GalleryPinchDetector({
    required this.child,
    required this.enabled,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    super.key,
  });

  @override
  State<GalleryPinchDetector> createState() => _GalleryPinchDetectorState();
}

class _GalleryPinchDetectorState extends State<GalleryPinchDetector> {
  _GalleryPinchGestureRecognizer? _recognizer;

  @override
  void didUpdateWidget(covariant GalleryPinchDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.enabled) _recognizer?.cancel();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _GalleryPinchGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _GalleryPinchGestureRecognizer
            >(
              () => _recognizer = _GalleryPinchGestureRecognizer(
                debugOwner: this,
              ),
              (recognizer) => recognizer
                ..enabled = widget.enabled
                ..onStart = widget.onStart
                ..onUpdate = widget.onUpdate
                ..onEnd = widget.onEnd,
            ),
      },
      child: widget.child,
    );
  }
}

class _GalleryPinchGestureRecognizer extends OneSequenceGestureRecognizer {
  bool enabled = true;
  ValueChanged<Offset>? onStart;
  void Function(double scale, Offset localFocalPoint)? onUpdate;
  ValueChanged<bool>? onEnd;

  final _positions = <int, Offset>{};
  final _accepted = <int>{};
  (int, int)? _pair;
  double _initialSpan = 0;
  bool _active = false;
  bool _blocked = false;
  bool _finished = false;

  _GalleryPinchGestureRecognizer({super.debugOwner})
    : super(supportedDevices: {PointerDeviceKind.touch});

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      enabled && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _positions[event.pointer] = event.localPosition;
    if (_blocked) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
    } else if (_finished || _active) {
      resolvePointer(event.pointer, GestureDisposition.accepted);
    } else if (_positions.length == 2) {
      _pair = (_positions.keys.first, _positions.keys.last);
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void acceptGesture(int pointer) {
    _accepted.add(pointer);
    final pair = _pair;
    if (!_active &&
        !_blocked &&
        !_finished &&
        pair != null &&
        _accepted.contains(pair.$1) &&
        _accepted.contains(pair.$2)) {
      final first = _positions[pair.$1]!;
      final second = _positions[pair.$2]!;
      _initialSpan = (first - second).distance;
      _active = true;
      invokeCallback("onStart", () => onStart?.call((first + second) / 2));
    }
  }

  @override
  void rejectGesture(int pointer) {
    _blocked = true;
    _end(cancelled: true);
    resolve(GestureDisposition.rejected);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!enabled) cancel();
    if (event is PointerMoveEvent) {
      _positions[event.pointer] = event.localPosition;
      final pair = _pair;
      if (_active &&
          pair != null &&
          (event.pointer == pair.$1 || event.pointer == pair.$2)) {
        final first = _positions[pair.$1]!;
        final second = _positions[pair.$2]!;
        final span = (first - second).distance;
        if (_initialSpan == 0) _initialSpan = span;
        final scale = _initialSpan == 0 ? 1.0 : span / _initialSpan;
        invokeCallback(
          "onUpdate",
          () => onUpdate?.call(scale, (first + second) / 2),
        );
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      final pair = _pair;
      if (event is PointerCancelEvent ||
          event.pointer == pair?.$1 ||
          event.pointer == pair?.$2) {
        _end(cancelled: event is PointerCancelEvent);
      }
      _positions.remove(event.pointer);
      _accepted.remove(event.pointer);
      resolvePointer(event.pointer, GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  void cancel() {
    _blocked = _positions.isNotEmpty;
    _end(cancelled: true);
    resolve(GestureDisposition.rejected);
  }

  void _end({required bool cancelled}) {
    if (!_active) return;
    _active = false;
    _finished = true;
    invokeCallback("onEnd", () => onEnd?.call(cancelled));
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _positions.clear();
    _accepted.clear();
    _pair = null;
    _active = false;
    _blocked = false;
    _finished = false;
  }

  @override
  String get debugDescription => "gallery pinch";
}
