import "dart:async";
import "dart:collection";
import "dart:io";
import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memories/memory_music_service.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/ui/common/offscreen_widget_tree.dart";
import "package:photos/ui/rewind/reel/rewind_reel.dart";
import "package:photos/ui/rewind/reel/rewind_video_format.dart";
import "package:photos/ui/rewind/reel/rewind_video_sink.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";

enum RewindVideoStage { preparing, rendering, finishing }

@immutable
class RewindVideoProgress {
  const RewindVideoProgress(this.stage, {this.frame = 0, this.frameCount = 1});

  final RewindVideoStage stage;
  final int frame;
  final int frameCount;

  double get fraction => switch (stage) {
    RewindVideoStage.preparing => 0,
    RewindVideoStage.rendering => frame / frameCount,
    RewindVideoStage.finishing => 1,
  };
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _MissingPhotos implements Exception {
  const _MissingPhotos();

  @override
  String toString() => "Some Rewind cards could not load their photos";
}

class RewindVideoJob with WidgetsBindingObserver {
  RewindVideoJob(
    BuildContext context, {
    required this.pages,
    this.reelOf = RewindReel.of,
    this.filePrefix = "ente-rewind-",
    this.directory,
    this.format = RewindVideoFormat.fullHd,
    this.loadMedia,
    this.track,
    bool foreground = false,
  }) : _media = MediaQuery.of(context),
       _locale =
           Localizations.maybeLocaleOf(context) ??
           ui.PlatformDispatcher.instance.locale,
       _direction = Directionality.of(context),
       _themes = InheritedTheme.capture(from: context, to: null),
       _foreground = foreground {
    WidgetsBinding.instance.addObserver(this);
    _video.future.ignore();
    _ended = _run();
  }

  static final _logger = Logger("RewindVideoJob");
  static const _musicTimeout = Duration(seconds: 10);
  static const _backgroundShare = 0.3;
  static const _framesInFlight = 3;
  static const _extendedRangeBlack = 384;
  static const _extendedRangeSpan = 510;
  static const _extendedRangePadding = 6;
  static final _extendedRangeFrames = _readsExtendedRange();
  static var _running = 0;

  final List<RewindPage> pages;
  final RewindReel Function(List<RewindPage> pages) reelOf;
  final String filePrefix;
  final Future<String> Function()? directory;
  final RewindVideoFormat format;
  final Future<bool> Function(List<RewindPage> pages)? loadMedia;
  final MemoryMusicTrack? track;
  final MediaQueryData _media;
  final Locale _locale;
  final TextDirection _direction;
  final CapturedThemes _themes;
  final _progress = ValueNotifier(
    const RewindVideoProgress(RewindVideoStage.preparing),
  );
  final _preview = ValueNotifier<ui.Image?>(null);
  ui.Image? _lastCard;
  final _time = ValueNotifier(Duration.zero);
  final _video = Completer<File>();
  final _cancellation = Completer<void>();
  final _loads = <Future<bool>>[];
  final _busy = Stopwatch();
  late final Future<void> _ended;
  var _wake = Completer<void>();
  var _resumed = _isResumed(WidgetsBinding.instance.lifecycleState);
  var _interrupted = false;
  var _inFront = true;
  bool _foreground;
  var _cost = Duration.zero;
  var _confirmed = 0;
  var _foregroundFrames = 0;
  var _failed = false;
  var _encodesWithFfmpeg = false;
  var _extendedRange = false;
  RewindReel? _reel;
  OffscreenWidgetTree? _tree;
  File? _file;

  ValueListenable<RewindVideoProgress> get progress => _progress;

  ValueListenable<ui.Image?> get preview => _preview;

  Future<File> get video => _video.future;

  File? get file => _file;

  bool get adoptable => _file == null && !_failed && !_cancellation.isCompleted;

  bool get isClip => _reel?.clip ?? false;

  set foreground(bool value) {
    if (value == _foreground) return;
    _foreground = value;
    _showPreview(value ? _lastCard?.clone() : null);
    if (!value && _encodesWithFfmpeg) unawaited(abort());
    _signal();
  }

  set inFront(bool value) {
    if (value == _inFront) return;
    _inFront = value;
    _signal();
  }

  Future<void> abort() {
    if (!_cancellation.isCompleted) _cancellation.complete();
    _tree?.stop();
    return _ended;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = _isResumed(state);
    if (!_resumed) _interrupted = true;
    _signal();
  }

  static bool _isResumed(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  Future<void> _run() async {
    try {
      final video = await _export();
      if (_cancellation.isCompleted) {
        await _delete(video);
        throw const _Cancelled();
      }
      _file = video;
      _video.complete(video);
    } catch (error, stackTrace) {
      if (error is! _Cancelled) {
        _logger.severe("Failed to export the Rewind video", error, stackTrace);
      }
      _failed = true;
      _video.completeError(error, stackTrace);
    } finally {
      WidgetsBinding.instance.removeObserver(this);
      if (!_foreground) _showPreview(null);
      _holdLastCard(null);
      _time.dispose();
    }
  }

  Future<File> _export() async {
    await _gate();
    final previews = VideoPreviewService.instance;
    _running++;
    RewindVideoSink? sink;
    try {
      if (_running == 1) await previews.pauseForExport();
      final music = await _unlessCancelled(_music());
      if (music == null && !_foreground) {
        _logger.info("Not pre-generating the Rewind video without its music");
        throw const _Cancelled();
      }
      final reel = _reel = await _loadReel();
      final directory =
          await this.directory?.call() ??
          Configuration.instance.getTempDirectory();
      await _deleteOldVideos(directory);
      final output = File(
        "$directory$filePrefix${DateTime.now().millisecondsSinceEpoch}.mp4",
      );
      final duration = reel.videoDuration;
      var native = true;
      while (true) {
        await _gate();
        if (!native && !_foreground) throw const _Cancelled();
        _interrupted = false;
        _encodesWithFfmpeg = !native;
        _extendedRange = native && await _extendedRangeFrames;
        sink = native
            ? RewindNativeVideoSink.open(
                output: output,
                format: format,
                frameRate: RewindReel.frameRate,
                duration: duration,
                music: music,
              )
            : RewindFfmpegVideoSink.open(
                output: output,
                format: format,
                frameRate: RewindReel.frameRate,
                duration: duration,
                music: music,
              );
        try {
          return await _encode(reel, sink);
        } on _Cancelled {
          rethrow;
        } on _MissingPhotos {
          rethrow;
        } catch (error, stackTrace) {
          if (!native || !(_foreground || _interrupted)) rethrow;
          _logger.warning(
            _interrupted
                ? "Restarting the Rewind video after the app left the foreground"
                : "Encoding the Rewind video with FFmpeg",
            error,
            stackTrace,
          );
          await sink.abort();
          sink = null;
          native = _interrupted;
        }
      }
    } catch (_) {
      _failed = true;
      await sink?.abort();
      rethrow;
    } finally {
      if (--_running == 0) previews.resumeAfterExport();
    }
  }

  Future<File> _encode(RewindReel reel, RewindVideoSink sink) async {
    final clock = Stopwatch()..start();
    await _unlessCancelled(sink.ready);
    await _render(reel, sink);
    final rendered = clock.elapsed;
    _progress.value = const RewindVideoProgress(RewindVideoStage.finishing);
    await _gate();
    final video = await sink.finish();
    _logger.info(
      "Rendered ${reel.frameCount + 1} frames in ${rendered.inMilliseconds} ms "
      "($_foregroundFrames in the foreground) and finished in "
      "${(clock.elapsed - rendered).inMilliseconds} ms with ${sink.runtimeType}",
    );
    return video;
  }

  Future<void> _render(RewindReel reel, RewindVideoSink sink) async {
    _progress.value = const RewindVideoProgress(RewindVideoStage.preparing);
    _foregroundFrames = 0;
    _holdLastCard(null);
    var written = Future<void>.value();
    try {
      if (_foreground) sink.prepareMusic();
      written = sink.add(await _cover(reel));
      _progress.value = RewindVideoProgress(
        RewindVideoStage.rendering,
        frameCount: reel.frameCount,
      );
      final tree = _mount(reel);
      final writing = Queue.of([written]);
      try {
        for (var frame = 0; frame < reel.frameCount; frame++) {
          await _advance(reel, tree, reel.timeOf(frame));
          _busy.stop();
          await _unlessCancelled(rewindRiveFilesLoaded());
          await _gate();
          _busy.start();
          final image = await tree.capture();
          if (frame == reel.storyEndFrame) _holdLastCard(image.clone());
          if (_foreground) {
            _foregroundFrames++;
            sink.prepareMusic();
            if (frame <= reel.storyEndFrame) _showPreview(image.clone());
          }
          final pixels = _read(image, extendedRange: _extendedRange)..ignore();
          if (!_foreground) await pixels;
          _cost = _busy.elapsed;
          final previous = written;
          written = previous.then((_) => pixels).then(sink.add)..ignore();
          writing.add(written);
          if (writing.length > _framesInFlight) {
            await _unlessCancelled(writing.removeFirst());
          }
          _progress.value = RewindVideoProgress(
            RewindVideoStage.rendering,
            frame: frame + 1,
            frameCount: reel.frameCount,
          );
        }
      } finally {
        _unmount(tree);
      }
      await _unlessCancelled(written);
    } catch (_) {
      written.ignore();
      rethrow;
    }
  }

  Future<ByteData> _cover(RewindReel reel) async {
    final tree = _mount(reel);
    try {
      for (var frame = 0; frame <= reel.coverFrame; frame++) {
        await _advance(reel, tree, reel.timeOf(frame));
        _cost = _busy.elapsed;
      }
      await _unlessCancelled(rewindRiveFilesLoaded());
      await _gate();
      await tree.advance();
      return await _read(await tree.capture());
    } finally {
      _unmount(tree);
    }
  }

  Future<void> _advance(
    RewindReel reel,
    OffscreenWidgetTree tree,
    Duration time,
  ) async {
    await _pace();
    await _loadShown(reel, time);
    await _gate();
    _busy
      ..reset()
      ..start();
    _time.value = time;
    await tree.advance();
  }

  OffscreenWidgetTree _mount(RewindReel reel) => _tree = OffscreenWidgetTree(
    size: RewindReel.canvas,
    pixelRatio: format.pixelRatio,
    frameRate: RewindReel.frameRate,
    child: _themes.wrap(
      MediaQuery(
        data: _media,
        child: Localizations(
          locale: _locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Directionality(
            textDirection: _direction,
            child: RewindReelView(
              reel: reel,
              time: _time,
              pixelRatio: format.pixelRatio,
            ),
          ),
        ),
      ),
    ),
  );

  void _unmount(OffscreenWidgetTree tree) {
    if (_tree == tree) _tree = null;
    tree.dispose();
  }

  Future<void> _pace() async {
    await _gate();
    if (_foreground) return;
    final rest = _cost * ((1 - _backgroundShare) / _backgroundShare);
    await _unlessCancelled(
      Future.any([Future<void>.delayed(rest), _wake.future]),
    );
    await _gate();
    if (_foreground) return;
    await _unlessCancelled(_afterLiveFrame());
    await _gate();
  }

  Future<void> _gate() async {
    while (!_resumed || !(_foreground || _inFront)) {
      await _unlessCancelled(_wake.future);
    }
    _throwIfCancelled();
  }

  Future<void> _afterLiveFrame() {
    final binding = SchedulerBinding.instance;
    if (!binding.hasScheduledFrame) return Future.value();
    final drawn = Completer<void>();
    binding.addPostFrameCallback((_) => drawn.complete());
    return Future.any([drawn.future, _wake.future]);
  }

  void _signal() {
    final wake = _wake;
    _wake = Completer();
    wake.complete();
  }

  Future<void> _loadShown(RewindReel reel, Duration time) async {
    final load = loadMedia;
    if (load == null) return;
    final scroll = reel.scrollAt(time);
    while (_loads.length < reel.pages.length &&
        reel.starts[_loads.length] < scroll + 2) {
      final loading = load([reel.pages[_loads.length]]);
      loading.ignore();
      _loads.add(loading);
    }
    while (_confirmed < _loads.length && reel.starts[_confirmed] < scroll + 1) {
      if (!await _unlessCancelled(_loads[_confirmed])) {
        throw const _MissingPhotos();
      }
      _confirmed++;
    }
  }

  Future<RewindReel> _loadReel() async {
    final warmed = _foreground
        ? await _unlessCancelled(
            Future.wait([for (final page in pages) page.warmUp()]),
          )
        : await _warmUpInTurn();
    if (warmed.contains(false)) {
      throw const _MissingPhotos();
    }
    return reelOf(pages);
  }

  Future<List<bool>> _warmUpInTurn() async {
    final warmed = <bool>[];
    for (final page in pages) {
      await _gate();
      warmed.add(await _unlessCancelled(page.warmUp()));
    }
    return warmed;
  }

  Future<File?> _music() async {
    try {
      final track = this.track ?? await _firstTrack();
      if (track == null) return null;
      return await RemoteAssetsService.instance
          .getAsset(
            track.url,
            cacheFileName: memoryMusicCacheFileName(track.url),
          )
          .timeout(_musicTimeout);
    } catch (error, stackTrace) {
      _logger.warning("Could not load the Rewind music", error, stackTrace);
      return null;
    }
  }

  Future<MemoryMusicTrack?> _firstTrack() async {
    final tracks = await rewindService.music.prepare().timeout(_musicTimeout);
    return tracks.firstOrNull;
  }

  Future<void> _deleteOldVideos(String directory) async {
    final old = RegExp("^${RegExp.escape(filePrefix)}\\d+\\.mp4");
    try {
      await for (final entry in Directory(directory).list()) {
        if (entry is File && old.hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
        }
      }
    } on FileSystemException catch (error, stackTrace) {
      _logger.warning("Could not clear old Rewind videos", error, stackTrace);
    }
  }

  Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      return;
    }
  }

  Future<ByteData> _read(ui.Image image, {bool extendedRange = false}) async {
    try {
      if (extendedRange) {
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawUnmodified,
        );
        if (data != null &&
            data.lengthInBytes == image.width * image.height * 8) {
          return data;
        }
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError("Could not read a Rewind video frame");
      return data;
    } finally {
      image.dispose();
    }
  }

  static Future<bool> _readsExtendedRange() async {
    if (!Platform.isIOS) return false;
    const color = Color(0xFF102030);
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = color);
    final image = await recorder.endRecording().toImage(1, 1);
    try {
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawUnmodified,
      );
      if (data == null || data.lengthInBytes != 8) return false;
      final expected = [
        for (final channel in [color.b, color.g, color.r, color.a])
          (_extendedRangeBlack + (channel * _extendedRangeSpan).round()) <<
              _extendedRangePadding,
      ];
      final actual = [
        for (var i = 0; i < 4; i++) data.getUint16(i * 2, Endian.little),
      ];
      return listEquals(actual, expected);
    } finally {
      image.dispose();
    }
  }

  void _showPreview(ui.Image? image) {
    final shown = _preview.value;
    _preview.value = image;
    shown?.dispose();
  }

  void _holdLastCard(ui.Image? image) {
    _lastCard?.dispose();
    _lastCard = image;
  }

  Future<T> _unlessCancelled<T>(Future<T> work) async {
    final result = await Future.any([
      work,
      _cancellation.future.then((_) => throw const _Cancelled()),
    ]);
    _throwIfCancelled();
    return result;
  }

  void _throwIfCancelled() {
    if (_cancellation.isCompleted) throw const _Cancelled();
  }
}
