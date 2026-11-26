import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:ffmpeg/ffmpeg.dart" as ffmpeg;
import "package:native_video_editor/native_video_editor.dart";
import "package:photos/services/ffmpeg_service.dart";
import "package:photos/ui/rewind/reel/rewind_video_format.dart";

abstract interface class RewindVideoSink {
  Future<void> get ready;

  void prepareMusic();

  Future<void> add(ByteData rgba);

  Future<File> finish();

  Future<void> abort();
}

const _fadeIn = Duration(milliseconds: 900);
const _fadeOut = Duration(milliseconds: 1500);
const _coverFilter =
    "scale=out_color_matrix=bt601:out_range=pc,format=yuv420p[cover]";
const _coverArguments = [
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
];

List<String> _musicArguments(Duration duration) {
  final fadeOutAt = (duration - _fadeOut).inMilliseconds / 1000;
  return [
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
  ];
}

String _seconds(Duration duration) =>
    "${duration.inMicroseconds / Duration.microsecondsPerSecond}";

Future<void> _delete(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    return;
  }
}

class RewindFfmpegVideoSink implements RewindVideoSink {
  RewindFfmpegVideoSink._(this.output, this._pipePath, this._job) {
    ready = _open()..ignore();
    unawaited(_watch());
  }

  final File output;
  final String _pipePath;
  final FfmpegJob _job;
  @override
  late final Future<void> ready;
  RandomAccessFile? _pipe;
  ffmpeg.Result? _result;
  var _write = Future<void>.value();
  var _closing = false;

  static RewindFfmpegVideoSink open({
    required File output,
    required RewindVideoFormat format,
    required int frameRate,
    required Duration duration,
    File? music,
  }) {
    final pipePath = "${output.path}.frames";
    final pixels = format.pixels;
    ffmpeg.createPipe(pipePath);
    return RewindFfmpegVideoSink._(
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
            "[still]select='eq(n,0)',$_coverFilter",
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
        ..._coverArguments,
        if (music != null) ..._musicArguments(duration),
        "-t",
        _seconds(duration),
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

  @override
  void prepareMusic() {}

  @override
  Future<void> add(ByteData rgba) => _write = _add(rgba);

  Future<void> _add(ByteData rgba) async {
    await ready;
    _throwIfEnded();
    if (_closing) throw StateError("The Rewind video is already closing");
    await _pipe!.writeFrom(
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
    );
  }

  @override
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

  @override
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
}

class RewindNativeVideoSink implements RewindVideoSink {
  RewindNativeVideoSink._(
    this.output,
    this._size,
    this._duration,
    this._music,
    this._stream,
  ) {
    ready = _stream.then<void>((_) {})..ignore();
  }

  final File output;
  final String _size;
  final Duration _duration;
  final File? _music;
  final Future<VideoFrameStream> _stream;
  @override
  late final Future<void> ready;
  var _write = Future<void>.value();
  var _hasCover = false;
  FfmpegJob? _job;
  FfmpegJob? _musicJob;
  Future<bool>? _encodedMusic;

  static RewindNativeVideoSink open({
    required File output,
    required RewindVideoFormat format,
    required int frameRate,
    required Duration duration,
    File? music,
  }) {
    final pixels = format.pixels;
    final width = pixels.width.round();
    final height = pixels.height.round();
    return RewindNativeVideoSink._(
      output,
      "${width}x$height",
      duration,
      music,
      NativeVideoEditor.openFrameStream(
        VideoFrameStreamRequest(
          outputPath: "${output.path}.video.mp4",
          width: width,
          height: height,
          frameRate: frameRate,
          bitrate: format.bitrate,
        ),
      ),
    );
  }

  String get _videoPath => "${output.path}.video.mp4";

  String get _coverPath => "${output.path}.cover.rgba";

  String get _musicPath => "${output.path}.music.m4a";

  @override
  void prepareMusic() {
    final music = _music;
    if (music == null || _encodedMusic != null) return;
    _encodedMusic = _encodeMusic(music);
  }

  Future<bool> _encodeMusic(File music) async {
    final job = _musicJob = FfmpegService.instance.start([
      "-y",
      "-stream_loop",
      "-1",
      "-i",
      music.path,
      "-vn",
      ..._musicArguments(_duration),
      "-t",
      _seconds(_duration),
      _musicPath,
    ]);
    final encoded = await job.completed.then(
      (result) => result.isSuccess,
      onError: (Object _) => false,
    );
    if (!encoded) await _delete(_musicPath);
    return encoded;
  }

  @override
  Future<void> add(ByteData rgba) => _write = _add(rgba);

  Future<void> _add(ByteData rgba) async {
    final stream = await _stream;
    if (!_hasCover) {
      _hasCover = true;
      await File(_coverPath).writeAsBytes(Uint8List.sublistView(rgba));
    }
    await stream.add(rgba);
  }

  @override
  Future<File> finish() async {
    await (await _stream).finish();
    final music = _music;
    final encodedMusic = await _encodedMusic ?? false;
    final musicInput = encodedMusic
        ? ["-i", _musicPath]
        : music == null
        ? const <String>[]
        : ["-stream_loop", "-1", "-i", music.path];
    final musicEncoding = encodedMusic
        ? const ["-c:a", "copy"]
        : music == null
        ? const <String>[]
        : _musicArguments(_duration);
    final job = _job = FfmpegService.instance.start([
      "-y",
      "-i",
      _videoPath,
      ...musicInput,
      "-f",
      "rawvideo",
      "-pixel_format",
      "rgba",
      "-video_size",
      _size,
      "-i",
      _coverPath,
      "-filter_complex",
      "[${music == null ? 1 : 2}:v]$_coverFilter",
      "-map",
      "0:v",
      if (music != null) ...["-map", "1:a:0"],
      "-map",
      "[cover]",
      "-c:v:0",
      "copy",
      ..._coverArguments,
      ...musicEncoding,
      "-t",
      _seconds(_duration),
      "-movflags",
      "+faststart",
      output.path,
    ]);
    try {
      final result = await job.completed;
      if (!result.isSuccess || !await output.exists()) {
        await _delete(output.path);
        throw StateError(
          "FFmpeg exited with ${result.returnCode}: ${result.output}",
        );
      }
      return output;
    } finally {
      await _delete(_videoPath);
      await _delete(_coverPath);
      await _delete(_musicPath);
    }
  }

  @override
  Future<void> abort() async {
    final cancelled = _job?.cancel();
    final musicCancelled = _musicJob?.cancel();
    await _stream
        .then((stream) => stream.cancel())
        .then<void>((_) {}, onError: (Object _) {});
    await _write.then<void>((_) {}, onError: (Object _) {});
    await cancelled;
    await musicCancelled;
    await _encodedMusic;
    await _delete(output.path);
    await _delete(_videoPath);
    await _delete(_coverPath);
    await _delete(_musicPath);
  }
}
