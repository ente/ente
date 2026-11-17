import "dart:async";
import "dart:io";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memories/memory_video_exporter.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

Future<File?> showMemoryVideoExportSheet(
  BuildContext context, {
  required List<EnteFile> files,
  required MemoryMusicTrack? musicTrack,
  required bool muteVideos,
  required String title,
}) async {
  final result = await showBottomSheetComponent<_MemoryVideoExportResult>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _MemoryVideoExportSheet(
      files: files,
      musicTrack: musicTrack,
      muteVideos: muteVideos,
      title: title,
    ),
  );
  if (result == null) return null;
  final error = result.error;
  if (error != null) Error.throwWithStackTrace(error, result.stackTrace!);
  return result.video;
}

class _MemoryVideoExportResult {
  final File? video;
  final Object? error;
  final StackTrace? stackTrace;

  const _MemoryVideoExportResult.succeeded(File this.video)
    : error = null,
      stackTrace = null;

  const _MemoryVideoExportResult.failed(
    Object this.error,
    StackTrace this.stackTrace,
  ) : video = null;
}

class _MemoryVideoExportSheet extends StatefulWidget {
  final List<EnteFile> files;
  final MemoryMusicTrack? musicTrack;
  final bool muteVideos;
  final String title;

  const _MemoryVideoExportSheet({
    required this.files,
    required this.musicTrack,
    required this.muteVideos,
    required this.title,
  });

  @override
  State<_MemoryVideoExportSheet> createState() =>
      _MemoryVideoExportSheetState();
}

class _MemoryVideoExportSheetState extends State<_MemoryVideoExportSheet> {
  final _exporter = MemoryVideoExporter();
  double _progress = 0;
  bool _isClosed = false;
  bool _holdsExportGuards = false;

  @override
  void initState() {
    super.initState();
    unawaited(_export());
  }

  @override
  void dispose() {
    if (!_isClosed) unawaited(_exporter.cancel());
    _releaseExportGuards();
    super.dispose();
  }

  Future<void> _export() async {
    _holdsExportGuards = true;
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.memoryVideoExport,
    );
    try {
      await VideoPreviewService.instance.pauseForExport();
      final video = await _exporter.export(
        files: widget.files,
        musicTrack: widget.musicTrack,
        muteVideos: widget.muteVideos,
        title: widget.title,
        onProgress: _setProgress,
      );
      _close(_MemoryVideoExportResult.succeeded(video));
    } on MemoryVideoExportCancelled {
      _close();
    } catch (e, s) {
      _close(_MemoryVideoExportResult.failed(e, s));
    } finally {
      _releaseExportGuards();
    }
  }

  void _releaseExportGuards() {
    if (!_holdsExportGuards) return;
    _holdsExportGuards = false;
    VideoPreviewService.instance.resumeAfterExport();
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.memoryVideoExport,
    );
  }

  void _setProgress(double progress) {
    if (!mounted) return;
    setState(() => _progress = progress.clamp(0.0, 1.0));
  }

  Future<void> _cancel() async {
    await _exporter.cancel();
    _releaseExportGuards();
    _close();
  }

  void _close([_MemoryVideoExportResult? result]) {
    if (_isClosed || !mounted) return;
    _isClosed = true;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context)!;
    if (route.isCurrent) {
      navigator.pop(result);
    } else {
      navigator.removeRoute(route, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: l10n.creatingVideo,
      illustration: _MemoryVideoPreview(files: widget.files),
      showCloseButton: false,
      isScrollable: true,
      shrinkWrap: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.keepEnteOpenUntilVideoIsReady,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.xl),
          Row(
            children: [
              Expanded(child: _MemoryVideoProgressBar(progress: _progress)),
              const SizedBox(width: Spacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40),
                child: Text(
                  "${(_progress * 100).floor()}%",
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyles.mini.copyWith(
                    color: colors.textBase,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        ButtonComponent(
          key: const ValueKey("memory-video-export-cancel"),
          label: l10n.cancel,
          variant: ButtonComponentVariant.secondary,
          onTap: _cancel,
        ),
      ],
    );
  }
}

class _MemoryVideoProgressBar extends StatelessWidget {
  final double progress;

  const _MemoryVideoProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress),
      duration: Motion.slow,
      curve: Curves.easeOut,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(Radii.xs),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 6,
          color: colors.primary,
          backgroundColor: colors.fillLight,
        ),
      ),
    );
  }
}

class _MemoryVideoPreview extends StatefulWidget {
  final List<EnteFile> files;

  const _MemoryVideoPreview({required this.files});

  @override
  State<_MemoryVideoPreview> createState() => _MemoryVideoPreviewState();
}

class _MemoryVideoPreviewState extends State<_MemoryVideoPreview> {
  static const _slideDuration = Duration(milliseconds: 2200);
  static const _maxHeight = 236.0;
  static const _maxScreenHeightFraction = 0.28;

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.files.length > 1) {
      _timer = Timer.periodic(_slideDuration, (_) {
        setState(() => _index = (_index + 1) % widget.files.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final height = math.min(
      _maxHeight,
      MediaQuery.sizeOf(context).height * _maxScreenHeightFraction,
    );
    return Container(
      width:
          height *
          MemoryVideoExporter.frameWidth /
          MemoryVideoExporter.frameHeight,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.strokeFaint),
      ),
      child: AnimatedSwitcher(
        duration: MemoryVideoExporter.crossfade,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: _SlowZoom(
          key: ValueKey(_index),
          zoomIn: _index.isEven,
          duration: _slideDuration + MemoryVideoExporter.crossfade,
          child: ThumbnailWidget(
            widget.files[_index],
            thumbnailSize: thumbnailLargeSize,
            shouldShowSyncStatus: false,
            shouldShowFavoriteIcon: false,
            shouldShowVideoOverlayIcon: false,
          ),
        ),
      ),
    );
  }
}

class _SlowZoom extends StatelessWidget {
  final bool zoomIn;
  final Duration duration;
  final Widget child;

  const _SlowZoom({
    super.key,
    required this.zoomIn,
    required this.duration,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const near = 1.12;
    const far = 1.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: zoomIn ? far : near, end: zoomIn ? near : far),
      duration: duration,
      curve: Curves.easeInOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}
