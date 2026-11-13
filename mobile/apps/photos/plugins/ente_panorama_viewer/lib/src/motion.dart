import "dart:async";
import "dart:math" as math;

import "package:ente_panorama_viewer/src/models.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

const _methodChannel = MethodChannel("io.ente.panorama_viewer/motion");
const _eventChannel = EventChannel("io.ente.panorama_viewer/motion_events");

Future<bool> isPanoramaMotionAvailable() async {
  return await _methodChannel.invokeMethod<bool>("isAvailable") ?? false;
}

class MotionController {
  MotionController(
    this.onViewDelta, {
    required this.onReferenceChanged,
    required this.onError,
    Stream<Object?> Function()? eventStream,
  }) : _eventStream =
           eventStream ?? (() => _eventChannel.receiveBroadcastStream());

  final ValueChanged<PanoramaView> onViewDelta;
  final VoidCallback onReferenceChanged;
  final void Function(Object error, StackTrace stackTrace) onError;
  final Stream<Object?> Function() _eventStream;

  // Cancelled by stop(), which is called on disable, pause, and disposal.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _subscription;
  final MotionViewTracker _tracker = MotionViewTracker();
  Future<void> _transition = Future.value();
  bool _shouldRun = false;
  bool _acceptEvents = false;
  bool _frameScheduled = false;
  int? _quarterTurns;
  _Quaternion? _pending;

  void start() {
    _shouldRun = true;
    unawaited(_queueTransition());
  }

  Future<void> stop() {
    _shouldRun = false;
    _deactivate();
    return _queueTransition();
  }

  Future<void> _queueTransition() {
    _transition = _transition.then((_) => _applyDesiredState()).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      onError(error, stackTrace);
    });
    return _transition;
  }

  Future<void> _applyDesiredState() async {
    if (_shouldRun) {
      if (_subscription != null) {
        _acceptEvents = true;
        return;
      }
      resetReference();
      _acceptEvents = true;
      try {
        _subscription = _eventStream().listen(
          _onEvent,
          onError: _onStreamError,
        );
      } catch (_) {
        _deactivate();
        rethrow;
      }
      return;
    }
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void _deactivate() {
    _acceptEvents = false;
    _pending = null;
    _frameScheduled = false;
    resetReference();
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _shouldRun = false;
    _deactivate();
    onError(error, stackTrace);
    unawaited(_queueTransition());
  }

  void resetReference() {
    _tracker.reset();
    _quarterTurns = null;
  }

  void _onEvent(Object? event) {
    if (!_acceptEvents) return;
    if (event is! List<Object?> || event.length < 5) return;
    final values = event.take(5).map((value) => (value as num).toDouble());
    final iterator = values.iterator;
    iterator.moveNext();
    final w = iterator.current;
    iterator.moveNext();
    final x = iterator.current;
    iterator.moveNext();
    final y = iterator.current;
    iterator.moveNext();
    final z = iterator.current;
    iterator.moveNext();
    final quarterTurns = iterator.current.round();
    if (_quarterTurns != null && _quarterTurns != quarterTurns) {
      onReferenceChanged();
      _tracker.reset();
    }
    _quarterTurns = quarterTurns;
    _pending = _screenAdjustedQuaternion(
      _Quaternion(w, x, y, z).normalized,
      quarterTurns,
    );
    if (_frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      final current = _pending;
      _pending = null;
      if (current == null || !_acceptEvents || _subscription == null) return;
      onViewDelta(_tracker._update(current));
    });
  }
}

class MotionViewTracker {
  _Quaternion? _reference;

  void reset() {
    _reference = null;
  }

  PanoramaView _update(_Quaternion current) {
    final reference = _reference;
    if (reference == null) {
      _reference = current;
      return const PanoramaView();
    }
    final relative = (reference.conjugate * current).normalized;
    final forward = relative.rotate(const _Vector3(0, 0, -1));
    return PanoramaView(
      longitude: math.atan2(forward.x, -forward.z) * 180 / math.pi,
      latitude: math.asin(forward.y.clamp(-1, 1)) * 180 / math.pi,
    );
  }

  PanoramaView updateValues({
    required double w,
    required double x,
    required double y,
    required double z,
  }) {
    return _update(_Quaternion(w, x, y, z).normalized);
  }

  PanoramaView updateScreenAdjustedValues({
    required double w,
    required double x,
    required double y,
    required double z,
    required int quarterTurns,
  }) {
    return _update(
      _screenAdjustedQuaternion(
        _Quaternion(w, x, y, z).normalized,
        quarterTurns,
      ),
    );
  }
}

_Quaternion _screenAdjustedQuaternion(_Quaternion attitude, int quarterTurns) {
  final angle = quarterTurns * math.pi / 2;
  final screenRotation = _Quaternion(
    math.cos(angle / 2),
    0,
    0,
    math.sin(angle / 2),
  );
  return attitude * screenRotation;
}

class _Quaternion {
  const _Quaternion(this.w, this.x, this.y, this.z);

  final double w;
  final double x;
  final double y;
  final double z;

  _Quaternion get normalized {
    final length = math.sqrt(w * w + x * x + y * y + z * z);
    if (length == 0) return const _Quaternion(1, 0, 0, 0);
    return _Quaternion(w / length, x / length, y / length, z / length);
  }

  _Quaternion get conjugate => _Quaternion(w, -x, -y, -z);

  _Quaternion operator *(_Quaternion other) {
    return _Quaternion(
      w * other.w - x * other.x - y * other.y - z * other.z,
      w * other.x + x * other.w + y * other.z - z * other.y,
      w * other.y - x * other.z + y * other.w + z * other.x,
      w * other.z + x * other.y - y * other.x + z * other.w,
    );
  }

  _Vector3 rotate(_Vector3 vector) {
    final result =
        this * _Quaternion(0, vector.x, vector.y, vector.z) * conjugate;
    return _Vector3(result.x, result.y, result.z);
  }
}

class _Vector3 {
  const _Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}
