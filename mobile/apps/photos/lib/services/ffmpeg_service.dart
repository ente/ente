import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:ffmpeg/ffmpeg.dart' as ffmpeg;
import 'package:photos/utils/ffprobe_util.dart';

class FfmpegJob {
  FfmpegJob._(this.arguments, this._onProgress);

  final List<String> arguments;
  final void Function(Duration)? _onProgress;
  final _completion = Completer<ffmpeg.Result>();
  void Function()? _cancelNative;
  bool _cancelled = false;
  Duration? _processedTime;

  Future<ffmpeg.Result> get completed => _completion.future;

  double? progress(Duration? duration) {
    if (duration == null || duration.inMicroseconds <= 0) return null;
    final time = _processedTime;
    if (time == null) return null;
    return (time.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);
  }

  Future<void> cancel() async {
    if (!_completion.isCompleted && !_cancelled) {
      _cancelled = true;
      if (_cancelNative case final cancel?) {
        cancel();
      } else {
        _completion.complete(const ffmpeg.Result(255, ''));
      }
    }
    await completed.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _updateProgress(Duration time) {
    if (_cancelled || _completion.isCompleted) return;
    _processedTime = time;
    _onProgress?.call(time);
  }
}

class FfmpegService {
  FfmpegService({
    ffmpeg.Session Function(void Function(Duration)) createSession =
        ffmpeg.Session.new,
  }) : _createSession = createSession;

  static final instance = FfmpegService();

  final ffmpeg.Session Function(void Function(Duration)) _createSession;
  final _queue = Queue<FfmpegJob>();
  bool _running = false;

  FfmpegJob start(
    List<String> arguments, {
    void Function(Duration)? onProgress,
  }) {
    if (RootIsolateToken.instance == null) {
      throw StateError('Submit FFmpeg jobs from the root isolate.');
    }
    final job = FfmpegJob._(List.unmodifiable(arguments), onProgress);
    _queue.add(job);
    unawaited(_drain());
    return job;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeFirst();
        if (job._cancelled) continue;
        try {
          final session = _createSession(job._updateProgress);
          job._cancelNative = session.cancel;
          final result = await session.execute(job.arguments);
          job._completion.complete(result);
        } catch (error, stack) {
          job._completion.completeError(error, stack);
        } finally {
          job._cancelNative = null;
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<Map> getVideoInfo(String path) async =>
      FFProbeUtil.getMetadata(await ffmpeg.probeMedia(path));
}
