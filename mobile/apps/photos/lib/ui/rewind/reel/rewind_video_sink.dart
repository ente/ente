import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:ffmpeg/ffmpeg.dart" as ffmpeg;
import "package:photos/services/ffmpeg_service.dart";
import "package:photos/ui/rewind/reel/rewind_video_format.dart";

class RewindVideoSink {
  RewindVideoSink._(this.output, this._pipePath, this._job) {
    ready = _open()..ignore();
    unawaited(_watch());
  }

  static const _fadeIn = Duration(milliseconds: 900);
  static const _fadeOut = Duration(milliseconds: 1500);

  final File output;
  final String _pipePath;
  final FfmpegJob _job;
  late final Future<void> ready;
  RandomAccessFile? _pipe;
  ffmpeg.Result? _result;
  var _write = Future<void>.value();
  var _closing = false;

  static RewindVideoSink open({
    required File output,
    required RewindVideoFormat format,
    required int frameRate,
    required Duration duration,
    File? music,
  }) {
    final pipePath = "${output.path}.frames";
    final pixels = format.pixels;
    ffmpeg.createPipe(pipePath);
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    final fadeOutAt = (duration - _fadeOut).inMilliseconds / 1000;
    return RewindVideoSink._(
      output,
      pipePath,
      FfmpegService.instance.start([
        "-y",
        "-f",
        "rawvideo",
        "-pixel_format",
        "rgba",
        "-video_size",
        "${pixels.width.round()}x${pixels.height.round()}",
        "-framerate",
        "$frameRate",
        "-i",
        pipePath,
        if (music != null) ...["-stream_loop", "-1", "-i", music.path],
        "-filter_complex",
        "[0:v]split[film][still];"
            "[film]scale=out_color_matrix=bt709:out_range=tv,"
            "format=yuv420p[video];"
            "[still]select='eq(n,0)',"
            "scale=out_color_matrix=bt601:out_range=pc,format=yuv420p[cover]",
        "-map",
        "[video]",
        if (music != null) ...["-map", "1:a:0"],
        "-map",
        "[cover]",
        ...format.encoder,
        "-colorspace:v:0",
        "bt709",
        "-color_primaries:v:0",
        "bt709",
        "-color_trc:v:0",
        "bt709",
        "-color_range:v:0",
        "tv",
        "-c:v:1",
        "mjpeg",
        "-q:v:1",
        "3",
        "-color_range:v:1",
        "pc",
        "-fps_mode:v:1",
        "passthrough",
        "-disposition:v:1",
        "attached_pic",
        if (music != null) ...[
          "-af",
          "afade=t=in:d=${_fadeIn.inMilliseconds / 1000},"
              "afade=t=out:st=$fadeOutAt:d=${_fadeOut.inMilliseconds / 1000}",
          "-c:a",
          "aac",
          "-b:a",
          "128k",
          "-ar",
          "44100",
          "-ac",
          "2",
        ],
        "-t",
        "$seconds",
        "-movflags",
        "+faststart",
        output.path,
      ]),
    );
  }

  Future<void> _open() async {
    _pipe = await File(_pipePath).open(mode: FileMode.writeOnly);
  }

  Future<void> _watch() async {
    try {
      _result = await _job.completed;
    } catch (error) {
      _result = ffmpeg.Result(-1, "$error");
    }
    if (!_closing) File(_pipePath).openRead().drain<void>().ignore();
  }

  Future<void> add(ByteData rgba) => _write = _add(rgba);

  Future<void> _add(ByteData rgba) async {
    await ready;
    _throwIfEnded();
    if (_closing) throw StateError("The Rewind video is already closing");
    await _pipe!.writeFrom(
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
    );
  }

  Future<File> finish() async {
    await ready;
    _throwIfEnded();
    _closing = true;
    await _pipe?.close();
    _pipe = null;
    final result = await _job.completed;
    await _delete(_pipePath);
    if (!result.isSuccess || !await output.exists()) {
      await _delete(output.path);
      throw StateError(
        "FFmpeg exited with ${result.returnCode}: ${result.output}",
      );
    }
    return output;
  }

  Future<void> abort() async {
    final cancelled = _job.cancel();
    await ready.then<void>((_) {}, onError: (Object _) {});
    _closing = true;
    await _write.then<void>((_) {}, onError: (Object _) {});
    await _closePipe();
    await cancelled;
    await _delete(_pipePath);
    await _delete(output.path);
  }

  Future<void> _closePipe() async {
    final pipe = _pipe;
    _pipe = null;
    try {
      await pipe?.close();
    } on FileSystemException {
      return;
    }
  }

  void _throwIfEnded() {
    final result = _result;
    if (result == null) return;
    throw StateError(
      "FFmpeg stopped with ${result.returnCode}: ${result.output}",
    );
  }

  static Future<void> _delete(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      return;
    }
  }
}
