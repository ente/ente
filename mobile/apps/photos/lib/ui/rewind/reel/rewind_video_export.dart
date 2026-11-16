import "dart:async";
import "dart:io";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memories/memory_music_service.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/rewind/reel/rewind_frame_stepper.dart";
import "package:photos/ui/rewind/reel/rewind_reel.dart";
import "package:photos/ui/rewind/reel/rewind_video_format.dart";
import "package:photos/ui/rewind/reel/rewind_video_sink.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_confetti.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_swap_in.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";
import "package:photos/utils/dialog_util.dart";
import "package:share_plus/share_plus.dart";

final _videos = Expando<File>();

Future<void> shareRewindVideo(
  BuildContext context, {
  required List<RewindPage> pages,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
  Rect? origin,
}) async {
  var video = _videos[pages];
  if (video == null || !await video.exists()) {
    if (!context.mounted) return;
    final result = await Navigator.of(context).push(
      RewindVideoExportPage(
        pages: pages,
        loadMedia: loadMedia,
        track: track,
      ).route(),
    );
    if (result is! File) {
      if (result != null && context.mounted) {
        await showGenericErrorBottomSheet(context: context, error: result);
      }
      return;
    }
    video = _videos[pages] = result;
  }
  if (!context.mounted || !_isInFront(context)) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(video.path, mimeType: "video/mp4")],
      sharePositionOrigin: origin,
    ),
  );
}

bool _isInFront(BuildContext context) =>
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
    _isOnTop(context);

bool _isOnTop(BuildContext context) {
  final route = ModalRoute.of(context);
  return route == null || route.isCurrent && _isOnTop(route.navigator!.context);
}

class RewindVideoExportPage extends StatefulWidget {
  const RewindVideoExportPage({
    required this.pages,
    this.format = RewindVideoFormat.fullHd,
    this.loadMedia,
    this.track,
    super.key,
  });

  final List<RewindPage> pages;
  final RewindVideoFormat format;
  final Future<bool> Function(List<RewindPage> pages)? loadMedia;
  final MemoryMusicTrack? track;

  Route<Object?> route() => PageRouteBuilder<Object?>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => this,
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  @override
  State<RewindVideoExportPage> createState() => _RewindVideoExportPageState();
}

enum _Stage { preparing, rendering, finishing }

class _Cancelled implements Exception {
  const _Cancelled();
}

class _RewindVideoExportPageState extends State<RewindVideoExportPage>
    with WidgetsBindingObserver {
  static final _logger = Logger("RewindVideoExport");
  static const _filePrefix = "ente-rewind-";
  static const _musicTimeout = Duration(seconds: 10);
  static const _wrapHold = Duration(milliseconds: 900);
  static const _longestCountedFrame = Duration(milliseconds: 500);
  static const _background = Color(0xFF1A2A8F);
  static const _stripes = Color(0xFF22349F);
  static const _frame = Rect.fromLTWH(77, 160, 236, 420);
  static const _ducky = Rect.fromLTWH(2, 498, 148, 186);
  static const _bar = Rect.fromLTWH(164, 648, 202, 24);
  static const _quips = [
    "Rewinding the tape",
    "Picking your best angles",
    "Teaching Ducky to edit",
    "Adding the soundtrack",
    "Polishing every frame",
    "Rolling the credits",
  ];

  final _boundary = GlobalKey();
  final _time = ValueNotifier(Duration.zero);
  final _frameIndex = ValueNotifier(0);
  final _clock = Stopwatch();
  final _cancellation = Completer<void>();
  var _rendered = Duration.zero;
  RewindFrameStepper? _stepper;
  RewindReel? _reel;
  var _stage = _Stage.preparing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    _time.dispose();
    _frameIndex.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _stepper?.resume();
  }

  Future<void> _run() async {
    Object? result;
    try {
      result = await _export();
    } on _Cancelled {
      result = null;
    } catch (error, stackTrace) {
      _logger.severe("Failed to export the Rewind video", error, stackTrace);
      result = error;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    if (route.isCurrent) {
      navigator.pop(result);
    } else {
      navigator.removeRoute(route, result);
    }
  }

  Future<File> _export() async {
    final previews = VideoPreviewService.instance;
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.rewindVideoExport,
    );
    RewindVideoSink? sink;
    try {
      await previews.pauseForExport();
      final music = await _unlessCancelled(_music());
      final reel = await _unlessCancelled(_loadReel());
      final directory = Configuration.instance.getTempDirectory();
      await _deleteOldVideos(directory);
      sink = RewindVideoSink.open(
        output: File(
          "$directory$_filePrefix${DateTime.now().millisecondsSinceEpoch}.mp4",
        ),
        format: widget.format,
        frameRate: RewindReel.frameRate,
        duration: reel.duration + reel.timeOf(1),
        music: music,
      );
      await _unlessCancelled(sink.ready);
      await _render(reel, sink);
      if (mounted) setState(() => _stage = _Stage.finishing);
      final wrap = Future<void>.delayed(_wrapHold);
      final video = await sink.finish();
      await wrap;
      return video;
    } catch (_) {
      await sink?.abort();
      rethrow;
    } finally {
      previews.resumeAfterExport();
      wakeLockService.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.rewindVideoExport,
      );
    }
  }

  Future<void> _deleteOldVideos(String directory) async {
    try {
      await for (final entry in Directory(directory).list()) {
        if (entry is File &&
            entry.uri.pathSegments.last.startsWith(_filePrefix)) {
          await entry.delete();
        }
      }
    } on FileSystemException catch (error, stackTrace) {
      _logger.warning("Could not clear old Rewind videos", error, stackTrace);
    }
  }

  Future<File?> _music() async {
    try {
      final track = widget.track ?? await _firstTrack();
      if (track == null) return null;
      return await RemoteAssetsService.instance
          .getAsset(
            track.url,
            cacheFileName: memoryMusicCacheFileName(track.url),
          )
          .timeout(_musicTimeout);
    } catch (error, stackTrace) {
      _logger.warning("Exporting without music", error, stackTrace);
      return null;
    }
  }

  Future<MemoryMusicTrack?> _firstTrack() async {
    final tracks = await MemoryMusicService.instance.prepare().timeout(
      _musicTimeout,
    );
    return tracks.firstOrNull;
  }

  Future<RewindReel> _loadReel() async {
    final warmed = await Future.wait([
      for (final page in widget.pages) page.warmUp(),
    ]);
    final reel = RewindReel.of(widget.pages);
    final ready =
        !warmed.contains(false) &&
        (await widget.loadMedia?.call(reel.pages) ?? true);
    if (!ready) {
      throw StateError("Some Rewind cards could not load their photos");
    }
    return reel;
  }

  Future<void> _render(RewindReel reel, RewindVideoSink sink) async {
    if (!mounted) throw const _Cancelled();
    _throwIfCancelled();
    setState(() => _reel = reel);
    final stepper = _stepper = RewindFrameStepper(RewindReel.frameRate)
      ..install();
    var written = Future<void>.value();
    try {
      written = sink.add(await _cover(reel, stepper));
      if (!mounted) throw const _Cancelled();
      setState(() => _stage = _Stage.rendering);
      _clock.start();
      for (var frame = 0; frame < reel.frameCount; frame++) {
        _time.value = reel.timeOf(frame);
        _frameIndex.value = frame;
        await _unlessCancelled(stepper.step());
        final pixels = _read(await _capture())..ignore();
        final previous = written;
        written = previous.then((_) => pixels).then(sink.add);
        await previous;
        final lap = _clock.elapsed;
        _clock.reset();
        _rendered += lap < _longestCountedFrame ? lap : _longestCountedFrame;
      }
      await _unlessCancelled(written);
    } catch (_) {
      written.ignore();
      rethrow;
    } finally {
      _clock.stop();
      _stepper = null;
      stepper.uninstall();
    }
  }

  Future<ByteData> _cover(RewindReel reel, RewindFrameStepper stepper) async {
    for (var frame = 0; frame <= reel.coverFrame; frame++) {
      _time.value = reel.timeOf(frame);
      await _unlessCancelled(stepper.step());
    }
    await _unlessCancelled(rewindRiveFilesLoaded());
    await _unlessCancelled(stepper.step());
    return _read(await _capture());
  }

  Future<ui.Image> _capture() {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: widget.format.pixelRatio);
  }

  Future<ByteData> _read(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError("Could not read a Rewind video frame");
      return data;
    } finally {
      image.dispose();
    }
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

  void _cancel() {
    if (_stage == _Stage.finishing || _cancellation.isCompleted) return;
    _cancellation.complete();
  }

  double _progress(int frame) => switch (_stage) {
    _Stage.preparing => 0,
    _Stage.rendering => frame / _reel!.frameCount,
    _Stage.finishing => 1,
  };

  String _quip(int frame) => switch (_stage) {
    _Stage.preparing => "Getting your photos ready",
    _Stage.rendering =>
      _quips[(_progress(frame) * _quips.length).floor().clamp(
        0,
        _quips.length - 1,
      )],
    _Stage.finishing => "That’s a wrap!",
  };

  String _timeLeft(int frame) {
    const warmUpFrames = 30;
    if (_stage == _Stage.finishing) return "Ready to share";
    if (_stage == _Stage.preparing || frame < warmUpFrames) {
      return "Keep Ente open, this won’t take long";
    }
    final left =
        _rendered.inMilliseconds / frame * (_reel!.frameCount - frame) / 1000;
    if (left < 5) return "Almost there";
    return "About ${(left / 5).ceil() * 5} seconds left";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const RewindBackdrop(
                color: _background,
                pattern: RewindStripes(_stripes),
              ),
              RewindStage(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 84,
                    child: Center(
                      child: RewindOutlinedText(
                        "MAKING YOUR VIDEO",
                        style: RewindTextStyles.display(
                          31,
                          color: RewindColors.yellow,
                          height: 1,
                          letterSpacing: 0.4,
                        ),
                        outline: 2.6,
                        shadow: const Offset(2, 3),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: _frame,
                    child: Transform.rotate(angle: -0.026, child: _preview()),
                  ),
                  Positioned.fromRect(
                    rect: _ducky,
                    child: const IgnorePointer(
                      child: RewindDucky(RewindAssets.cameraDucky),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: _frameIndex,
                    builder: (context, frame, _) => _status(frame),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 766,
                    child: Center(child: _cancelButton()),
                  ),
                  if (_stage == _Stage.finishing)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: RewindConfetti(count: 70, active: true),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(int frame) {
    final progress = _progress(frame);
    final quip = _quip(frame);
    return Stack(
      children: [
        Positioned(
          left: _bar.left,
          top: 594,
          child: RewindOutlinedText(
            "${(progress * 100).floor()}%",
            style: RewindTextStyles.display(
              44,
              color: RewindColors.white,
              height: 1,
            ),
            outline: 3,
            shadow: const Offset(2.4, 3.2),
          ),
        ),
        Positioned.fromRect(rect: _bar, child: _ProgressBar(progress)),
        Positioned(
          left: 20,
          right: 20,
          top: 700,
          child: RewindSwapIn(
            text: quip,
            child: Text(
              quip,
              textAlign: TextAlign.center,
              style: RewindTextStyles.body(19, height: 1.2),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 730,
          child: Text(
            _timeLeft(frame),
            textAlign: TextAlign.center,
            style: RewindTextStyles.body(
              14,
              color: RewindColors.cream.withValues(alpha: 0.75),
              weight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cancelButton() {
    return Opacity(
      opacity: _stage == _Stage.finishing ? 0 : 1,
      child: Semantics(
        button: true,
        label: "Cancel",
        child: RewindPressable(
          onTap: _cancel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(
                color: RewindColors.cream.withValues(alpha: 0.6),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(99),
            ),
            child: ExcludeSemantics(
              child: Text(
                "Cancel",
                style: RewindTextStyles.body(15, height: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          left: 6,
          top: 7,
          right: -6,
          bottom: -7,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: RewindColors.ink,
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: RewindColors.cream,
            border: Border.all(color: RewindColors.ink, width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_reel case final reel?)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox.fromSize(
                        size: RewindReel.canvas,
                        child: RepaintBoundary(
                          key: _boundary,
                          child: RewindReelView(
                            key: ValueKey(_stage == _Stage.preparing),
                            reel: reel,
                            time: _time,
                            pixelRatio: widget.format.pixelRatio,
                          ),
                        ),
                      ),
                    ),
                  if (_stage == _Stage.preparing)
                    ColoredBox(
                      color: RewindColors.green,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Image.file(
                          RewindAssets.file(RewindAssets.coverLockup),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 18,
          child: _RecordingTag(active: _stage == _Stage.rendering),
        ),
      ],
    );
  }
}

class _RecordingTag extends StatelessWidget {
  const _RecordingTag({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: RewindColors.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RewindElapsed(
            active: active,
            builder: (context, ms) => Opacity(
              opacity: active && (ms ~/ 500).isOdd ? 0.25 : 1,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 8),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            "REC",
            style: RewindTextStyles.body(11, height: 1.1, letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar(this.progress);

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          left: 3,
          top: 4,
          right: -3,
          bottom: -4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: RewindColors.ink,
              borderRadius: BorderRadius.all(Radius.circular(99)),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: RewindColors.cream,
            border: Border.all(color: RewindColors.ink, width: 3),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [RewindColors.hotPink, RewindColors.candyPink],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
