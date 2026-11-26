import "dart:async";
import "dart:io";
import "dart:math";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/models/user_details.dart";
import "package:photos/module/upload/service/file_uploader.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/reel/rewind_reel.dart";
import "package:photos/ui/rewind/reel/rewind_video_job.dart";
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
import "package:photos/utils/gallery_save_title.dart";
import "package:receive_sharing_intent/receive_sharing_intent.dart";
import "package:share_plus/share_plus.dart";

final _videos = Expando<File>();
final _galleryAssets = Expando<AssetEntity>();
final _saveLogger = Logger("RewindVideoSave");
final _pregenerationLogger = Logger("RewindVideoPregeneration");
const _saveCheckTimeout = Duration(seconds: 10);
const _headroomFrames = 120;
const _headroomTimeout = Duration(seconds: 5);
const _headroomShare = 0.5;

Future<RewindVideoJob?> pregenerateRewindVideo(
  BuildContext context, {
  required List<RewindPage> pages,
  required bool Function() wanted,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
}) async {
  if (!context.mounted) return null;
  final key = _videoKeyOf(context, pages);
  await _recallKeptVideo(pages, key);
  final cached = _videos[pages];
  if (cached != null && await cached.exists()) return null;
  if (!context.mounted) return null;
  final refreshRate = View.of(context).display.refreshRate;
  if (!await _hasFrameHeadroom(refreshRate) || !context.mounted || !wanted()) {
    return null;
  }
  return _fullVideoJob(
    context,
    pages: pages,
    videoKey: key,
    loadMedia: loadMedia,
    track: track,
  );
}

typedef _VideoKey = ({String fingerprint, int generation});

_VideoKey? _videoKeyOf(BuildContext context, List<RewindPage> pages) {
  final fingerprint = rewindService.videoFingerprint(
    pages,
    Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale,
  );
  if (fingerprint == null) return null;
  return (fingerprint: fingerprint, generation: rewindService.videoGeneration);
}

Future<void> _recallKeptVideo(List<RewindPage> pages, _VideoKey? key) async {
  if (key == null || _videos[pages] != null) return;
  _videos[pages] = await rewindService.keptVideo(key.fingerprint);
}

RewindVideoJob _fullVideoJob(
  BuildContext context, {
  required List<RewindPage> pages,
  required _VideoKey? videoKey,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
  bool foreground = false,
}) {
  final job = RewindVideoJob(
    context,
    pages: pages,
    directory: videoKey == null ? null : rewindService.videoDirectory,
    loadMedia: loadMedia,
    track: track,
    foreground: foreground,
  );
  job.video.then((video) async {
    _videos[pages] = video;
    if (videoKey != null) {
      await rewindService.keepVideo(
        videoKey.fingerprint,
        videoKey.generation,
        video,
      );
    }
  }).ignore();
  return job;
}

Future<bool> _hasFrameHeadroom(double refreshRate) async {
  final timings = <FrameTiming>[];
  final enough = Completer<void>();
  void collect(List<FrameTiming> batch) {
    timings.addAll(batch);
    if (timings.length >= _headroomFrames && !enough.isCompleted) {
      enough.complete();
    }
  }

  SchedulerBinding.instance.addTimingsCallback(collect);
  await enough.future.timeout(_headroomTimeout, onTimeout: () {});
  SchedulerBinding.instance.removeTimingsCallback(collect);
  if (timings.length < _headroomFrames) {
    _pregenerationLogger.info(
      "Skipped: only ${timings.length} frames drawn in "
      "${_headroomTimeout.inSeconds} s",
    );
    return false;
  }
  final costs = [
    for (final timing in timings)
      max(
        timing.buildDuration.inMicroseconds,
        timing.rasterDuration.inMicroseconds,
      ),
  ]..sort();
  final cost = costs[costs.length ~/ 2];
  final budget = Duration.microsecondsPerSecond / refreshRate;
  final fits = cost < budget * _headroomShare;
  _pregenerationLogger.info(
    "${fits ? "Starting" : "Skipped"}: median frame cost "
    "${(cost / 1000).toStringAsFixed(1)} ms of a "
    "${(budget / 1000).toStringAsFixed(1)} ms budget over "
    "${timings.length} frames",
  );
  return fits;
}

Future<void> shareRewindVideo(
  BuildContext context, {
  required List<RewindPage> pages,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
  RewindVideoJob? job,
  Rect? origin,
}) async {
  final video = await _exportRewindVideo(
    context,
    pages: pages,
    loadMedia: loadMedia,
    track: track,
    job: job,
  );
  if (!context.mounted) return;
  await _shareVideoFile(context, video, origin);
}

Future<void> shareRewindClip(
  BuildContext context, {
  required RewindPage page,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
  Rect? origin,
}) async {
  final video = await _export(
    context,
    cacheKey: page.clipKey,
    start: () => RewindVideoJob(
      context,
      pages: [?page.clipIntro, page],
      reelOf: RewindReel.clipOf,
      filePrefix: "ente-rewind-${page.key}-",
      loadMedia: loadMedia,
      track: track,
      foreground: true,
    ),
  );
  if (!context.mounted) return;
  await _shareVideoFile(context, video, origin);
}

Future<void> _shareVideoFile(
  BuildContext context,
  File? video,
  Rect? origin,
) async {
  if (video == null || !_isInFront(context)) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(video.path, mimeType: "video/mp4")],
      sharePositionOrigin: origin,
    ),
  );
}

Future<bool> saveRewindVideo(
  BuildContext context, {
  required List<RewindPage> pages,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
  RewindVideoJob? job,
}) async {
  final tappedAt = DateTime.now();
  final uncategorized = await CollectionsService.instance
      .getUncategorizedCollection()
      .timeout(_saveCheckTimeout);
  if (await _hasSavedVideo(uncategorized.id, tappedAt)) {
    if (context.mounted) {
      showShortToast(context, RewindCopy.of(context).alreadySaved);
    }
    return true;
  }
  if (!context.mounted) return false;
  final video = await _exportRewindVideo(
    context,
    pages: pages,
    loadMedia: loadMedia,
    track: track,
    job: job,
  );
  if (video == null || !context.mounted) return false;
  final fits = await _fitsInFreeStorage(video);
  if (!context.mounted) return false;
  if (!fits) {
    await showStorageFullSheet(context);
    return false;
  }
  final appContext = Navigator.of(context, rootNavigator: true).context;
  final asset = await _saveToGallery(video, tappedAt);
  if (!appContext.mounted) return false;
  final saved = asset == null
      ? await _uploadFromAppStorage(appContext, video, uncategorized.id, pages)
      : await CollectionActions(CollectionsService.instance)
            .addToCollection(
              appContext,
              uncategorized.id,
              false,
              picketAssets: [asset],
            )
            .catchError((_) => false);
  if (!saved) return false;
  _galleryAssets[video] = null;
  Bus.instance.fire(ForceReloadHomeGalleryEvent("rewindVideoSaved"));
  if (appContext.mounted) {
    final copy = RewindCopy.of(appContext);
    showShortToast(
      appContext,
      asset == null ? copy.backingUp : copy.savedAndBackingUp,
    );
  }
  return true;
}

String get _savedVideoName => "Ente Rewind ${RewindEdition.year}.mp4";

final _savedVideoTitles = RegExp(
  "^Ente Rewind ${RewindEdition.year}( \\(\\d+\\))?\\.mp4\$",
  caseSensitive: false,
);

Future<bool> _hasSavedVideo(int collectionID, DateTime tappedAt) async {
  final since = tappedAt.year > RewindEdition.year
      ? DateTime(RewindEdition.year + 1)
      : DateTime(tappedAt.year, tappedAt.month, tappedAt.day);
  final until = DateTime(tappedAt.year, tappedAt.month, tappedAt.day + 1);
  final result = await FilesDB.instance.getFilesInCollection(
    collectionID,
    since.microsecondsSinceEpoch,
    until.microsecondsSinceEpoch,
  );
  return result.files.any(
    (file) =>
        file.localID != null &&
        file.fileType == FileType.video &&
        _savedVideoTitles.hasMatch(file.title ?? ""),
  );
}

Future<AssetEntity?> _saveToGallery(File video, DateTime tappedAt) async {
  if (!permissionService.hasGrantedPermissions()) return null;
  try {
    final previous = _galleryAssets[video];
    if (previous != null && await previous.exists) return previous;
    final asset = await PhotoManager.editor.saveVideo(
      video,
      title: await getMediaStoreCompatibleTitle(_savedVideoName),
      creationDate: tappedAt,
    );
    return _galleryAssets[video] = asset.copyWith(
      title: _savedVideoName,
      createDateSecond: tappedAt.millisecondsSinceEpoch ~/ 1000,
    );
  } catch (error, stackTrace) {
    _saveLogger.warning(
      "Could not save the Rewind video to the gallery",
      error,
      stackTrace,
    );
    return null;
  }
}

Future<bool> _uploadFromAppStorage(
  BuildContext context,
  File video,
  int collectionID,
  List<RewindPage> pages,
) async {
  final staging = await Directory(
    Configuration.instance.getTempDirectory(),
  ).createTemp("rewind-save-");
  try {
    final staged = await video.copy("${staging.path}/$_savedVideoName");
    if (!context.mounted) return false;
    return await CollectionActions(CollectionsService.instance)
        .addToCollection(
          context,
          collectionID,
          false,
          sharedFiles: [
            SharedMediaFile(
              path: staged.path,
              type: SharedMediaType.video,
              duration: RewindReel.of(pages).videoDuration.inMilliseconds,
            ),
          ],
        )
        .catchError((_) => false);
  } finally {
    await _deleteStaging(staging);
  }
}

Future<void> _deleteStaging(Directory staging) async {
  try {
    await staging.delete(recursive: true);
  } on FileSystemException catch (error, stackTrace) {
    _saveLogger.warning(
      "Could not delete the staged Rewind video",
      error,
      stackTrace,
    );
  }
}

Future<bool> _fitsInFreeStorage(File video) async {
  if (await _isOverQuota()) return false;
  final userDetails = await _latestUserDetails();
  if (userDetails == null) return true;
  final sharedHeadroom = max(
    userDetails.getTotalStorage() - userDetails.getFamilyOrPersonalUsage(),
    0,
  );
  final freeStorage = min(userDetails.getFreeStorage(), sharedHeadroom);
  return await video.length() <= freeStorage + FileUploader.k20MBStorageBuffer;
}

Future<bool> _isOverQuota() async {
  try {
    await fileUploadGateway.validateUploadEligibility().timeout(
      _saveCheckTimeout,
    );
    return false;
  } on DioException catch (error) {
    return error.response?.statusCode == 426;
  } on TimeoutException {
    return false;
  }
}

Future<UserDetails?> _latestUserDetails() async {
  try {
    return await UserService.instance.getUserDetailsV2().timeout(
      _saveCheckTimeout,
    );
  } catch (_) {
    return UserService.instance.getCachedUserDetails();
  }
}

Future<File?> _exportRewindVideo(
  BuildContext context, {
  required List<RewindPage> pages,
  Future<bool> Function(List<RewindPage> pages)? loadMedia,
  MemoryMusicTrack? track,
  RewindVideoJob? job,
}) async {
  final key = _videoKeyOf(context, pages);
  await _recallKeptVideo(pages, key);
  if (!context.mounted) return null;
  return _export(
    context,
    cacheKey: pages,
    job: job,
    start: () => _fullVideoJob(
      context,
      pages: pages,
      videoKey: key,
      loadMedia: loadMedia,
      track: track,
      foreground: true,
    ),
  );
}

Future<File?> _export(
  BuildContext context, {
  required Object cacheKey,
  required RewindVideoJob Function() start,
  RewindVideoJob? job,
}) async {
  final cached = job?.file ?? _videos[cacheKey];
  if (cached != null && await cached.exists()) {
    return _videos[cacheKey] = cached;
  }
  final keepsJob = job != null && job.adoptable;
  if (job != null && !keepsJob) await job.abort();
  if (!context.mounted) return null;
  final export = RewindVideoExportPage(
    job: keepsJob ? job : start(),
    keepsJob: keepsJob,
  );
  final result = await Navigator.of(context).push(export.route());
  if (result is File) return _videos[cacheKey] = result;
  if (result != null && context.mounted) {
    await showGenericErrorBottomSheet(context: context, error: result);
  }
  return null;
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
    required this.job,
    required this.keepsJob,
    super.key,
  });

  final RewindVideoJob job;
  final bool keepsJob;

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

class _RewindVideoExportPageState extends State<RewindVideoExportPage> {
  static const _wrapHold = Duration(milliseconds: 900);
  static const _longestCountedFrame = Duration(milliseconds: 500);
  static const _warmUpFrames = 30;
  static const _background = Color(0xFF1A2A8F);
  static const _stripes = Color(0xFF22349F);
  static const _frame = Rect.fromLTWH(77, 160, 236, 420);
  static const _ducky = Rect.fromLTWH(2, 498, 148, 186);
  static const _bar = Rect.fromLTWH(164, 648, 202, 24);

  final _cancellation = Completer<void>();
  final _lap = Stopwatch();
  final _finishing = Stopwatch();
  var _rendered = Duration.zero;
  var _timedFrames = 0;
  late var _stage = _job.progress.value.stage;

  RewindVideoJob get _job => widget.job;

  @override
  void initState() {
    super.initState();
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.rewindVideoExport,
    );
    _job.foreground = true;
    _job.progress.addListener(_onProgress);
    _onProgress();
    unawaited(_wait());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    _job.progress.removeListener(_onProgress);
    _job.foreground = false;
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.rewindVideoExport,
    );
    super.dispose();
  }

  Future<void> _wait() async {
    Object? result;
    try {
      final video = await Future.any<File?>([
        _job.video,
        _cancellation.future.then((_) => null),
      ]);
      if (video != null) {
        final wrap = _wrapHold - _finishing.elapsed;
        if (wrap > Duration.zero) await Future<void>.delayed(wrap);
      }
      result = video;
    } catch (error) {
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

  void _onProgress() {
    final progress = _job.progress.value;
    if (progress.stage == RewindVideoStage.rendering) {
      if (_lap.isRunning) {
        final lap = _lap.elapsed;
        _rendered += lap < _longestCountedFrame ? lap : _longestCountedFrame;
        _timedFrames++;
      }
      _lap
        ..reset()
        ..start();
    } else {
      _lap
        ..stop()
        ..reset();
    }
    if (progress.stage == RewindVideoStage.finishing) {
      _finishing.start();
    } else {
      _finishing
        ..stop()
        ..reset();
    }
    if (progress.stage != _stage) setState(() => _stage = progress.stage);
  }

  void _cancel() {
    if (_cancellation.isCompleted ||
        _job.progress.value.stage == RewindVideoStage.finishing) {
      return;
    }
    _cancellation.complete();
    if (widget.keepsJob) {
      _job.foreground = false;
    } else {
      unawaited(_job.abort());
    }
  }

  RewindCopy get _copy => RewindCopy.of(context);

  String _quip(RewindVideoProgress progress) {
    final quips = _copy.videoQuips;
    return switch (progress.stage) {
      RewindVideoStage.preparing => _copy.videoPreparing,
      RewindVideoStage.rendering =>
        quips[(progress.fraction * quips.length).floor().clamp(
          0,
          quips.length - 1,
        )],
      RewindVideoStage.finishing =>
        _celebrates ? _copy.videoWrapped : quips.last,
    };
  }

  bool get _celebrates => !_job.isClip;

  String _timeLeft(RewindVideoProgress progress) {
    if (progress.stage == RewindVideoStage.finishing) return _copy.videoDone;
    if (progress.stage == RewindVideoStage.rendering &&
        _timedFrames >= _warmUpFrames) {
      final left =
          _rendered.inMilliseconds /
          _timedFrames *
          (progress.frameCount - progress.frame) /
          1000;
      if (left < 5) return _copy.videoAlmostDone;
    }
    return _copy.videoKeepOpen;
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
                      child: RewindFitWidth(
                        width: 350,
                        alignment: Alignment.center,
                        child: RewindOutlinedText(
                          _copy.videoTitle,
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
                    valueListenable: _job.progress,
                    builder: (context, progress, _) => _status(progress),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 766,
                    child: Center(child: _cancelButton()),
                  ),
                  if (_stage == RewindVideoStage.finishing && _celebrates)
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

  Widget _status(RewindVideoProgress progress) {
    final fraction = progress.fraction;
    final quip = _quip(progress);
    return Stack(
      children: [
        Positioned(
          left: _bar.left,
          top: 594,
          child: RewindOutlinedText(
            "${(fraction * 100).floor()}%",
            style: RewindTextStyles.display(
              44,
              color: RewindColors.white,
              height: 1,
            ),
            outline: 3,
            shadow: const Offset(2.4, 3.2),
          ),
        ),
        Positioned.fromRect(rect: _bar, child: _ProgressBar(fraction)),
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
            _timeLeft(progress),
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
      opacity: _stage == RewindVideoStage.finishing ? 0 : 1,
      child: Semantics(
        button: true,
        label: _copy.cancel,
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
                _copy.cancel,
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
              child: ValueListenableBuilder(
                valueListenable: _job.preview,
                builder: (context, frame, _) =>
                    frame == null || _stage == RewindVideoStage.preparing
                    ? ColoredBox(
                        color: RewindColors.green,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Image.file(
                            RewindAssets.file(RewindAssets.coverLockup),
                          ),
                        ),
                      )
                    : RawImage(
                        image: frame,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 18,
          top: 18,
          child: _RecordingTag(active: _stage == RewindVideoStage.rendering),
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
