import "dart:async";

import "package:flutter/foundation.dart";

enum VideoSeekPhase { idle, dragging, settling }

class VideoSeekState {
  final Duration position;
  final Duration? duration;
  final VideoSeekPhase phase;
  final int requestId;

  const VideoSeekState({
    required this.position,
    required this.duration,
    required this.phase,
    required this.requestId,
  });

  bool get isInteracting => phase != VideoSeekPhase.idle;

  @override
  bool operator ==(Object other) =>
      other is VideoSeekState &&
      other.position == position &&
      other.duration == duration &&
      other.phase == phase &&
      other.requestId == requestId;

  @override
  int get hashCode => Object.hash(position, duration, phase, requestId);

  VideoSeekState copyWith({
    Duration? position,
    Duration? duration,
    VideoSeekPhase? phase,
    int? requestId,
  }) {
    return VideoSeekState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      phase: phase ?? this.phase,
      requestId: requestId ?? this.requestId,
    );
  }
}

class VideoSeekController extends ChangeNotifier {
  static const _positionTolerance = Duration(milliseconds: 750);
  static const _reconciliationTimeout = Duration(seconds: 2);
  static const _sliderSeekInterval = Duration(milliseconds: 300);

  final Future<void> Function(Duration target) _seek;
  final Duration Function() _readPosition;
  final Duration? Function() _readDuration;
  final void Function(Object error, StackTrace stackTrace)? _onSeekError;

  VideoSeekState _state = const VideoSeekState(
    position: Duration.zero,
    duration: null,
    phase: VideoSeekPhase.idle,
    requestId: 0,
  );
  Duration _confirmedPosition = Duration.zero;
  Duration? _expectedPosition;
  Duration? _queuedTarget;
  bool _commandInFlight = false;
  bool _disposed = false;
  int _sessionId = 0;
  Timer? _reconciliationTimer;
  Timer? _sliderSeekTimer;

  VideoSeekController({
    required Future<void> Function(Duration target) seek,
    required Duration Function() readPosition,
    required Duration? Function() readDuration,
    void Function(Object error, StackTrace stackTrace)? onSeekError,
  }) : _seek = seek,
       _readPosition = readPosition,
       _readDuration = readDuration,
       _onSeekError = onSeekError;

  VideoSeekState get state => _state;

  Duration get position => _state.position;

  Duration? get duration => _state.duration ?? _readDuration();

  bool get canSeek {
    final duration = this.duration;
    return duration != null && duration > Duration.zero;
  }

  void updateDuration(Duration? duration) {
    if (_disposed || _state.duration == duration) return;
    _setState(_state.copyWith(duration: duration));
  }

  void beginSliderInteraction() {
    if (_disposed || !canSeek) return;
    _sliderSeekTimer?.cancel();
    _sliderSeekTimer = null;
    _setState(_state.copyWith(phase: VideoSeekPhase.dragging));
  }

  void updateSliderTarget(Duration target) {
    if (_disposed || _state.phase != VideoSeekPhase.dragging) return;
    _setOptimisticTarget(target, VideoSeekPhase.dragging);
    if (_sliderSeekTimer?.isActive ?? false) return;
    _sliderSeekTimer = Timer(_sliderSeekInterval, () {
      _sliderSeekTimer = null;
      _startCommandDrain();
    });
  }

  void endSliderInteraction(Duration target) {
    if (_disposed || _state.phase != VideoSeekPhase.dragging) return;
    _sliderSeekTimer?.cancel();
    _sliderSeekTimer = null;
    _setOptimisticTarget(target, VideoSeekPhase.settling);
    _startCommandDrain();
  }

  Duration seekBy(Duration delta) {
    if (_disposed) return _state.position;
    _sliderSeekTimer?.cancel();
    _sliderSeekTimer = null;
    final target = _clamp(_state.position + delta);
    if (target == _state.position) return target;
    _setOptimisticTarget(target, VideoSeekPhase.settling);
    _startCommandDrain();
    return _state.position;
  }

  void onPlayerPosition(Duration position, {Duration? duration}) {
    if (_disposed) return;
    if (duration != null) updateDuration(duration);

    if (_state.phase == VideoSeekPhase.dragging) return;

    final expected = _expectedPosition;
    if (expected != null) {
      if ((position - expected).abs() > _positionTolerance) {
        return;
      }
      _clearReconciliation();
    }

    _confirmedPosition = position;
    _setState(
      _state.copyWith(
        position: position,
        phase: _commandInFlight || _queuedTarget != null
            ? VideoSeekPhase.settling
            : VideoSeekPhase.idle,
      ),
    );
  }

  void reset({Duration position = Duration.zero, Duration? duration}) {
    if (_disposed) return;
    _sessionId++;
    _sliderSeekTimer?.cancel();
    _sliderSeekTimer = null;
    _queuedTarget = null;
    _clearReconciliation();
    _confirmedPosition = position;
    _setState(
      VideoSeekState(
        position: position,
        duration: duration,
        phase: VideoSeekPhase.idle,
        requestId: _state.requestId + 1,
      ),
    );
  }

  void _setOptimisticTarget(Duration target, VideoSeekPhase phase) {
    final clampedTarget = _clamp(target);
    final requestId = _state.requestId + 1;
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    _queuedTarget = clampedTarget;
    _expectedPosition = clampedTarget;
    _setState(
      _state.copyWith(
        position: clampedTarget,
        phase: phase,
        requestId: requestId,
      ),
    );
  }

  Duration _clamp(Duration target) {
    final duration = this.duration;
    if (duration == null || duration <= Duration.zero) {
      return target < Duration.zero ? Duration.zero : target;
    }
    if (target < Duration.zero) return Duration.zero;
    if (target > duration) return duration;
    return target;
  }

  void _startCommandDrain() {
    if (_commandInFlight || _disposed) return;
    unawaited(_drainCommands());
  }

  Future<void> _drainCommands() async {
    _commandInFlight = true;
    final sessionId = _sessionId;
    try {
      while (!_disposed && sessionId == _sessionId) {
        final target = _queuedTarget;
        if (target == null) break;
        final requestId = _state.requestId;
        _queuedTarget = null;
        try {
          await _seek(target);
          if (!_disposed &&
              sessionId == _sessionId &&
              requestId == _state.requestId &&
              _queuedTarget == null &&
              _expectedPosition != null) {
            _scheduleReconciliation(sessionId, requestId);
          }
        } catch (error, stackTrace) {
          if (_disposed || sessionId != _sessionId) return;
          if (_state.requestId != requestId || _queuedTarget != null) {
            continue;
          }
          _clearReconciliation();
          _queuedTarget = null;
          _setState(
            _state.copyWith(
              position: _confirmedPosition,
              phase: VideoSeekPhase.idle,
            ),
          );
          _onSeekError?.call(error, stackTrace);
          return;
        }
      }
    } finally {
      _commandInFlight = false;
      if (!_disposed) {
        if (_queuedTarget != null) {
          _startCommandDrain();
        } else if (sessionId == _sessionId &&
            _expectedPosition == null &&
            _state.phase != VideoSeekPhase.dragging) {
          _setState(_state.copyWith(phase: VideoSeekPhase.idle));
        }
      }
    }
  }

  void _scheduleReconciliation(int sessionId, int requestId) {
    _reconciliationTimer?.cancel();
    _reconciliationTimer = Timer(_reconciliationTimeout, () {
      if (_disposed ||
          sessionId != _sessionId ||
          requestId != _state.requestId ||
          _expectedPosition == null ||
          _commandInFlight ||
          _state.phase == VideoSeekPhase.dragging ||
          _queuedTarget != null) {
        return;
      }
      final position = _clamp(_readPosition());
      _clearReconciliation();
      _confirmedPosition = position;
      _setState(
        _state.copyWith(position: position, phase: VideoSeekPhase.idle),
      );
    });
  }

  void _clearReconciliation() {
    _reconciliationTimer?.cancel();
    _reconciliationTimer = null;
    _expectedPosition = null;
  }

  void _setState(VideoSeekState state) {
    if (_disposed || _state == state) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionId++;
    _reconciliationTimer?.cancel();
    _sliderSeekTimer?.cancel();
    super.dispose();
  }
}
