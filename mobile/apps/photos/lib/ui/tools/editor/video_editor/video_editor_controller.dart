import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:video_player/video_player.dart';

enum VideoRotationDirection { left, right }

Duration scaledVideoDuration(Duration duration, double speed) =>
    Duration(microseconds: (duration.inMicroseconds / speed).round());

class VideoMinimumDurationError implements Exception {
  const VideoMinimumDurationError(this.minimum, this.actual);

  final Duration minimum;
  final Duration actual;
}

class VideoEditorState {
  const VideoEditorState({
    required this.startTrim,
    required this.endTrim,
    required this.minCrop,
    required this.maxCrop,
    required this.rotation,
    required this.preferredCropAspectRatio,
    required this.speed,
  });

  final Duration startTrim;
  final Duration endTrim;
  final Offset minCrop;
  final Offset maxCrop;
  final int rotation;
  final double? preferredCropAspectRatio;
  final double speed;
}

class VideoEditorController extends ChangeNotifier {
  VideoEditorController.file(
    this.file, {
    this.minDuration = const Duration(seconds: 1),
  }) : video = VideoPlayerController.file(file);

  final File file;
  final Duration minDuration;
  final VideoPlayerController video;

  NativeVideoInfo? _videoInfo;
  bool _initialized = false;
  bool _disposed = false;
  bool _handlingTrimBoundary = false;
  Duration _startTrim = Duration.zero;
  Duration _endTrim = Duration.zero;
  Offset _minCrop = Offset.zero;
  Offset _maxCrop = const Offset(1, 1);
  int _rotation = 0;
  double? _preferredCropAspectRatio;
  double _speed = 1.0;

  bool get initialized => _initialized;
  NativeVideoInfo get videoInfo => _videoInfo!;
  Duration get videoDuration => video.value.duration;
  Duration get startTrim => _startTrim;
  Duration get endTrim => _endTrim;
  Duration get trimmedDuration => _endTrim - _startTrim;
  Duration get videoPosition => video.value.position;
  bool get isPlaying => video.value.isPlaying;
  bool get isTrimmed =>
      _startTrim != Duration.zero || _endTrim != videoDuration;
  Offset get minCrop => _minCrop;
  Offset get maxCrop => _maxCrop;
  int get rotation => _rotation;
  double? get preferredCropAspectRatio => _preferredCropAspectRatio;
  double get speed => _speed;
  Duration get editedDuration => scaledVideoDuration(trimmedDuration, _speed);

  void updateSpeed(double speed) {
    if (!speed.isFinite || speed <= 0) {
      throw ArgumentError.value(speed, 'speed');
    }
    if (_speed == speed) return;
    _speed = speed;
    if (video.value.isInitialized) {
      unawaited(video.setPlaybackSpeed(speed));
    }
    notifyListeners();
  }

  set preferredCropAspectRatio(double? ratio) {
    if (ratio != null && (!ratio.isFinite || ratio <= 0)) {
      throw ArgumentError.value(ratio, 'ratio');
    }
    _preferredCropAspectRatio = ratio;
    if (ratio != null) {
      _fitCropToDisplayAspectRatio(ratio);
    }
    notifyListeners();
  }

  Size get sourceDisplaySize => Size(
    videoInfo.displayWidth.toDouble(),
    videoInfo.displayHeight.toDouble(),
  );

  Rect get normalizedCropRect =>
      Rect.fromLTRB(_minCrop.dx, _minCrop.dy, _maxCrop.dx, _maxCrop.dy);

  Rect get visualNormalizedCropRect =>
      rotateNormalizedRect(normalizedCropRect, _rotation);

  Future<void> initialize() async {
    final values = await Future.wait<dynamic>([
      video.initialize(),
      NativeVideoEditor.inspectVideo(file.path),
    ]);
    if (_disposed) return;
    _videoInfo = values[1] as NativeVideoInfo;

    if (videoDuration < minDuration) {
      throw VideoMinimumDurationError(minDuration, videoDuration);
    }

    _endTrim = videoDuration;
    video.addListener(_onVideoChanged);
    _initialized = true;
    notifyListeners();
  }

  void updateTrim(Duration start, Duration end) {
    final boundedStart = _clampDuration(start, Duration.zero, videoDuration);
    final boundedEnd = _clampDuration(end, Duration.zero, videoDuration);
    if (boundedEnd - boundedStart < minDuration) {
      return;
    }
    _startTrim = boundedStart;
    _endTrim = boundedEnd;
    if (videoPosition < _startTrim || videoPosition > _endTrim) {
      unawaited(video.seekTo(_startTrim));
    }
    notifyListeners();
  }

  void updateCrop(Offset minCrop, Offset maxCrop) {
    final rect = Rect.fromLTRB(
      minCrop.dx.clamp(0.0, 1.0),
      minCrop.dy.clamp(0.0, 1.0),
      maxCrop.dx.clamp(0.0, 1.0),
      maxCrop.dy.clamp(0.0, 1.0),
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    _minCrop = rect.topLeft;
    _maxCrop = rect.bottomRight;
    notifyListeners();
  }

  void updateVisualCrop(Rect visualRect) {
    final sourceRect = rotateNormalizedRect(visualRect, 360 - _rotation);
    updateCrop(sourceRect.topLeft, sourceRect.bottomRight);
  }

  void rotate90Degrees(VideoRotationDirection direction) {
    final delta = direction == VideoRotationDirection.right ? 90 : -90;
    _rotation = (_rotation + delta) % 360;
    if (_rotation < 0) _rotation += 360;
    if (_preferredCropAspectRatio != null) {
      _preferredCropAspectRatio = 1 / _preferredCropAspectRatio!;
    }
    notifyListeners();
  }

  VideoEditorState snapshot() => VideoEditorState(
    startTrim: _startTrim,
    endTrim: _endTrim,
    minCrop: _minCrop,
    maxCrop: _maxCrop,
    rotation: _rotation,
    preferredCropAspectRatio: _preferredCropAspectRatio,
    speed: _speed,
  );

  void restore(VideoEditorState state) {
    _startTrim = state.startTrim;
    _endTrim = state.endTrim;
    _minCrop = state.minCrop;
    _maxCrop = state.maxCrop;
    _rotation = state.rotation;
    _preferredCropAspectRatio = state.preferredCropAspectRatio;
    updateSpeed(state.speed);
    if (videoPosition < _startTrim || videoPosition > _endTrim) {
      unawaited(video.seekTo(_startTrim));
    }
    notifyListeners();
  }

  void _fitCropToDisplayAspectRatio(double displayRatio) {
    final sourceRatio = _rotation == 90 || _rotation == 270
        ? 1 / displayRatio
        : displayRatio;
    final size = sourceDisplaySize;
    final normalizedRatio = sourceRatio * size.height / size.width;
    final current = normalizedCropRect;
    var width = current.width;
    var height = current.height;
    if (width / height > normalizedRatio) {
      width = height * normalizedRatio;
    } else {
      height = width / normalizedRatio;
    }
    final center = current.center;
    final left = (center.dx - width / 2).clamp(0.0, 1.0 - width);
    final top = (center.dy - height / 2).clamp(0.0, 1.0 - height);
    _minCrop = Offset(left, top);
    _maxCrop = Offset(left + width, top + height);
  }

  void _onVideoChanged() {
    if (!_initialized) return;
    if (!_handlingTrimBoundary &&
        video.value.isPlaying &&
        video.value.position >= _endTrim) {
      _handlingTrimBoundary = true;
      video.seekTo(_startTrim).whenComplete(() {
        _handlingTrimBoundary = false;
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    video.removeListener(_onVideoChanged);
    unawaited(video.dispose());
    super.dispose();
  }

  static Duration _clampDuration(
    Duration value,
    Duration minimum,
    Duration maximum,
  ) {
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
  }
}

Rect rotateNormalizedRect(Rect rect, int clockwiseDegrees) {
  switch (clockwiseDegrees % 360) {
    case 0:
      return rect;
    case 90:
      return Rect.fromLTRB(
        1 - rect.bottom,
        rect.left,
        1 - rect.top,
        rect.right,
      );
    case 180:
      return Rect.fromLTRB(
        1 - rect.right,
        1 - rect.bottom,
        1 - rect.left,
        1 - rect.top,
      );
    case 270:
      return Rect.fromLTRB(
        rect.top,
        1 - rect.right,
        rect.bottom,
        1 - rect.left,
      );
    default:
      throw ArgumentError.value(clockwiseDegrees, 'clockwiseDegrees');
  }
}
