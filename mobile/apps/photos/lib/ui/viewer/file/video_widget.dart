import "dart:async";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:fluttertoast/fluttertoast.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/stream_switched_event.dart";
import "package:photos/events/use_media_kit_for_video.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/preview/playlist_data.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_widget_media_kit.dart";
import "package:photos/ui/viewer/file/video_widget_native.dart";

class VideoWidget extends StatefulWidget {
  final EnteFile file;
  final String? tagPrefix;
  final FullScreenRequestCallback? playbackCallback;
  final Function(bool)? shouldDisableScroll;
  final Function({required int memoryDuration})? onFinalFileLoad;
  final bool isFromMemories;

  const VideoWidget(
    this.file, {
    this.tagPrefix,
    this.playbackCallback,
    this.shouldDisableScroll,
    this.onFinalFileLoad,
    this.isFromMemories = false,
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
  late bool selectPreviewForPlay = widget.file.localID == null;
  PlaylistData? playlistData;
  final nativePlayerKey = GlobalKey();
  final mediaKitKey = GlobalKey();

  bool isPreviewLoadable = false;

  @override
  void initState() {
    super.initState();
    // Automatic error fallback: switch to MediaKit when native player fails
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
        // For shared video, we need to on-demand check if the file is streamable
        // and if not, we need to set isPreviewLoadable to false
        isPreviewLoadable = true;
      }
      _checkForPreview();
    }
  }

  @override
  void dispose() {
    useMediaKitForVideoSubscription.cancel();
    super.dispose();
  }

  Future<void> _checkForPreview() async {
    if (!widget.file.isOwner) {
      final bool isStreamable = await VideoPreviewService.instance
          .isSharedFileStreamble(widget.file);
      if (!isStreamable && mounted) {
        isPreviewLoadable = false;
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playPreview = isPreviewLoadable && selectPreviewForPlay;
    if (playPreview && playlistData == null) {
      return Center(
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
    }

    final shouldUseNativeVideoPlayer =
        useNativeVideoPlayer && (!playPreview || Platform.isAndroid);

    if (shouldUseNativeVideoPlayer) {
      return VideoWidgetNative(
        widget.file,
        key: nativePlayerKey,
        tagPrefix: widget.tagPrefix,
        playbackCallback: widget.playbackCallback,
        shouldDisableScroll: widget.shouldDisableScroll,
        playlistData: playlistData,
        selectedPreview: playPreview,
        isFromMemories: widget.isFromMemories,
        onStreamChange: () {
          setState(() {
            selectPreviewForPlay = !selectPreviewForPlay;
            Bus.instance.fire(
              StreamSwitchedEvent(
                selectPreviewForPlay,
                Platform.isAndroid && useNativeVideoPlayer
                    ? PlayerType.nativeVideoPlayer
                    : PlayerType.mediaKit,
              ),
            );
          });
        },
        onFinalFileLoad: widget.onFinalFileLoad,
      );
    }
    return VideoWidgetMediaKit(
      widget.file,
      key: mediaKitKey,
      tagPrefix: widget.tagPrefix,
      playbackCallback: widget.playbackCallback,
      shouldDisableScroll: widget.shouldDisableScroll,
      preview: playlistData?.preview,
      selectedPreview: playPreview,
      isFromMemories: widget.isFromMemories,
      onStreamChange: () {
        setState(() {
          selectPreviewForPlay = !selectPreviewForPlay;
          Bus.instance.fire(
            StreamSwitchedEvent(
              selectPreviewForPlay,
              Platform.isAndroid
                  ? PlayerType.nativeVideoPlayer
                  : PlayerType.mediaKit,
            ),
          );
        });
      },
      onFinalFileLoad: widget.onFinalFileLoad,
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
