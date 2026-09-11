import "dart:async";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:fluttertoast/fluttertoast.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/stream_switched_event.dart";
import "package:photos/events/use_media_kit_for_video.dart";
import "package:photos/events/video_preview_state_changed_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/preview/playlist_data.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_stream_change.dart";
import "package:photos/ui/viewer/file/video_widget_media_kit.dart";
import "package:photos/ui/viewer/file/video_widget_native.dart";

class VideoWidget extends StatefulWidget {
  final EnteFile file;
  final String? tagPrefix;
  final FullScreenRequestCallback? playbackCallback;
  final Function(bool)? shouldDisableScroll;
  final Function({required int memoryDuration})? onFinalFileLoad;
  final bool isFromMemories;
  final bool isActive;
  final int? itemIndex;
  final ValueListenable<int>? activeItemIndexListenable;
  final bool? isAudioMutedOverride;
  final ValueNotifier<double>? playbackSpeed;
  final VideoStreamChangeController? streamChangeController;

  const VideoWidget(
    this.file, {
    this.tagPrefix,
    this.playbackCallback,
    this.shouldDisableScroll,
    this.onFinalFileLoad,
    this.isFromMemories = false,
    required this.isActive,
    this.itemIndex,
    this.activeItemIndexListenable,
    this.isAudioMutedOverride,
    this.playbackSpeed,
    this.streamChangeController,
    super.key,
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  final _logger = Logger("VideoWidget");
  bool useNativeVideoPlayer = true;
  late final StreamSubscription<UseMediaKitForVideo>
  useMediaKitForVideoSubscription;
  StreamSubscription<VideoPreviewStateChangedEvent>?
  _videoPreviewStateChangedSubscription;
  late bool selectPreviewForPlay = widget.file.localID == null;
  PlaylistData? playlistData;
  final nativePlayerKey = GlobalKey();
  final mediaKitKey = GlobalKey();
  late final ValueNotifier<double> _playbackSpeed =
      widget.playbackSpeed ?? ValueNotifier<double>(1.0);

  bool isPreviewLoadable = false;
  bool _isCheckingPreview = false;
  bool _isCurrentlyProcessing = false;
  PreviewItemStatus? _processingStatus;

  bool get _isActive =>
      widget.isActive &&
      (widget.activeItemIndexListenable == null ||
          widget.activeItemIndexListenable!.value == widget.itemIndex);

  @override
  void initState() {
    super.initState();
    widget.activeItemIndexListenable?.addListener(_onActiveItemChanged);
    _refreshProcessingState();
    if (widget.streamChangeController != null) {
      _videoPreviewStateChangedSubscription = Bus.instance
          .on<VideoPreviewStateChangedEvent>()
          .listen(_onVideoPreviewStateChanged);
    }
    useMediaKitForVideoSubscription = Bus.instance
        .on<UseMediaKitForVideo>()
        .listen((event) {
          _logger.info(
            "Automatically switching to MediaKit due to native player error",
          );
          setState(() {
            useNativeVideoPlayer = false;
          });
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowTransformToast();
    });
    if (widget.file.isUploaded) {
      isPreviewLoadable = fileDataService.previewIds.containsKey(
        widget.file.uploadedFileID,
      );
      if (!widget.file.isOwner) {
        // Shared previews are discovered on demand; assume loadable until checked.
        isPreviewLoadable = true;
      }
      _publishStreamChangeState();
      _checkForPreview();
    } else {
      _publishStreamChangeState();
    }
  }

  @override
  void dispose() {
    widget.activeItemIndexListenable?.removeListener(_onActiveItemChanged);
    _videoPreviewStateChangedSubscription?.cancel();
    widget.streamChangeController?.clear(this);
    useMediaKitForVideoSubscription.cancel();
    if (widget.playbackSpeed == null) {
      _playbackSpeed.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.activeItemIndexListenable,
      widget.activeItemIndexListenable,
    )) {
      oldWidget.activeItemIndexListenable?.removeListener(_onActiveItemChanged);
      widget.activeItemIndexListenable?.addListener(_onActiveItemChanged);
    }
    if (oldWidget.streamChangeController != widget.streamChangeController) {
      oldWidget.streamChangeController?.clear(this);
      _videoPreviewStateChangedSubscription?.cancel();
      _videoPreviewStateChangedSubscription =
          widget.streamChangeController == null
          ? null
          : Bus.instance.on<VideoPreviewStateChangedEvent>().listen(
              _onVideoPreviewStateChanged,
            );
      _publishStreamChangeState();
    }
  }

  void _onActiveItemChanged() => setState(() {});

  Future<void> _checkForPreview() async {
    if (_isCheckingPreview) return;
    _isCheckingPreview = true;
    try {
      await _loadPreview();
    } finally {
      _isCheckingPreview = false;
    }
  }

  Future<void> _loadPreview() async {
    if (!widget.file.isOwner) {
      final bool isStreamable = await VideoPreviewService.instance
          .isSharedFileStreamble(widget.file);
      if (!isStreamable && mounted) {
        isPreviewLoadable = false;
        _publishStreamChangeState();
        setState(() {});
      }
    }
    if (!isPreviewLoadable) {
      return;
    }
    widget.playbackCallback?.call(
      false,
      FullScreenRequestReason.playbackStateChange,
    );
    final data = await VideoPreviewService.instance
        .getPlaylist(widget.file)
        .onError((error, stackTrace) {
          if (!mounted) return;
          _logger.warning(
            "Failed to download preview video",
            error,
            stackTrace,
          );
          Fluttertoast.showToast(msg: "Failed to download preview!");
          return null;
        });
    if (!mounted) return;
    if (data != null) {
      if (flagService.internalUser &&
          data.size != null &&
          widget.file.fileSize != null) {
        final size = formatBytes(widget.file.fileSize!);
        showToast(
          context,
          gravity: ToastGravity.TOP,
          "[i] Preview OG Size ($size), previewSize: ${formatBytes(data.size!)}",
        );
      }
      playlistData = data;
    } else {
      isPreviewLoadable = false;
    }
    _publishStreamChangeState();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playPreview = isPreviewLoadable && selectPreviewForPlay;
    final Widget child;
    if (playPreview && playlistData == null) {
      child = Center(
        child: Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: strokeFaintDark, width: 1),
          ),
          child: const EnteLoadingWidget(
            size: 32,
            color: fillBaseDark,
            padding: 0,
          ),
        ),
      );
    } else {
      final shouldUseNativeVideoPlayer =
          useNativeVideoPlayer &&
          !widget.file.isDeviceTrash &&
          (!playPreview || Platform.isAndroid);

      child = shouldUseNativeVideoPlayer
          ? VideoWidgetNative(
              widget.file,
              key: nativePlayerKey,
              tagPrefix: widget.tagPrefix,
              playbackCallback: widget.playbackCallback,
              shouldDisableScroll: widget.shouldDisableScroll,
              playlistData: playlistData,
              selectedPreview: playPreview,
              playbackSpeed: _playbackSpeed,
              isFromMemories: widget.isFromMemories,
              isActive: _isActive,
              isAudioMutedOverride: widget.isAudioMutedOverride,
              onFinalFileLoad: widget.onFinalFileLoad,
            )
          : VideoWidgetMediaKit(
              widget.file,
              key: mediaKitKey,
              tagPrefix: widget.tagPrefix,
              playbackCallback: widget.playbackCallback,
              shouldDisableScroll: widget.shouldDisableScroll,
              preview: playlistData?.preview,
              selectedPreview: playPreview,
              playbackSpeed: _playbackSpeed,
              isFromMemories: widget.isFromMemories,
              isActive: _isActive,
              isAudioMutedOverride: widget.isAudioMutedOverride,
              onFinalFileLoad: widget.onFinalFileLoad,
            );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: child,
    );
  }

  void _changeStream() {
    if (!isPreviewLoadable || _isCurrentlyProcessing) return;
    setState(() {
      selectPreviewForPlay = !selectPreviewForPlay;
      Bus.instance.fire(
        StreamSwitchedEvent(
          selectPreviewForPlay,
          Platform.isAndroid && useNativeVideoPlayer
              ? PlayerType.nativeVideoPlayer
              : PlayerType.mediaKit,
          fileTag: widget.file.tag,
        ),
      );
    });
    _publishStreamChangeState();
  }

  void _onVideoPreviewStateChanged(VideoPreviewStateChangedEvent event) {
    if (event.fileId != widget.file.uploadedFileID) return;
    _processingStatus = event.status;
    _isCurrentlyProcessing = switch (event.status) {
      PreviewItemStatus.inQueue ||
      PreviewItemStatus.retry ||
      PreviewItemStatus.compressing ||
      PreviewItemStatus.uploading => true,
      _ => false,
    };
    if (event.status == PreviewItemStatus.uploaded &&
        !isPreviewLoadable &&
        fileDataService.previewIds.containsKey(widget.file.uploadedFileID)) {
      isPreviewLoadable = true;
      _checkForPreview();
    }
    _publishStreamChangeState();
  }

  void _refreshProcessingState() {
    final fileID = widget.file.uploadedFileID;
    _isCurrentlyProcessing = VideoPreviewService.instance.isCurrentlyProcessing(
      fileID,
    );
    _processingStatus = fileID == null
        ? null
        : VideoPreviewService.instance.getProcessingStatus(fileID);
  }

  void _publishStreamChangeState() {
    final controller = widget.streamChangeController;
    if (controller == null) return;
    if (!isPreviewLoadable && !_isCurrentlyProcessing) {
      controller.clear(this);
      return;
    }
    controller.update(
      this,
      VideoStreamChangeState(
        isPreviewPlayer: selectPreviewForPlay,
        isCurrentlyProcessing: _isCurrentlyProcessing,
        processingStatus: _processingStatus,
        onStreamChange: _changeStream,
      ),
    );
  }

  void _maybeShowTransformToast() {
    if (!kDebugMode) return;
    final name = widget.file.title ?? widget.file.displayName;
    final editedIndex = name.indexOf('_edited');
    if (editedIndex == -1) return;
    final prefix = name.substring(0, editedIndex);

    final hasTrim = prefix.contains('_t');
    final cropMatch = RegExp(r'_c_([0-9]+(?:[:_-][0-9]+)?)').firstMatch(prefix);
    final rotateMatch = RegExp(r'_r_([^_]+)').firstMatch(prefix);

    if (!hasTrim && cropMatch == null && rotateMatch == null) return;

    final parts = <String>[];
    if (hasTrim) {
      parts.add('Trim applied');
    }
    if (cropMatch != null) {
      final raw = cropMatch.group(1) ?? '';
      final formatted = raw.replaceAll(RegExp('[:_-]'), ':');
      parts.add('Crop: $formatted');
    }
    if (rotateMatch != null) {
      parts.add('Rotate: ${rotateMatch.group(1)}°');
    }

    if (parts.isEmpty) return;
    showToast(
      context,
      parts.join(' • '),
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.TOP,
    );
  }
}
