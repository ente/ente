import "dart:async";
import "dart:io";

import "package:ente_strings/ente_strings.dart";
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/metadata/file_magic.dart";
import 'package:photos/module/download/file.dart';
import "package:photos/services/file_magic_service.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";
import "package:photos/states/detail_page_state.dart";
import 'package:photos/ui/notification/toast.dart';
import "package:photos/ui/viewer/file/live_image_long_press_router.dart";
import "package:photos/ui/viewer/file/qr_code_detection_helper.dart";
import 'package:photos/ui/viewer/file/zoomable_image.dart';

class ZoomableLiveImageNew extends StatefulWidget {
  final EnteFile enteFile;
  final Function(bool)? shouldDisableScroll;
  final String? tagPrefix;
  final Decoration? backgroundDecoration;
  final bool isFromMemories;
  final Function({required int memoryDuration})? onFinalFileLoad;
  final ValueChanged<File>? onFinalImageLoaded;
  final ValueNotifier<QrCodeDetectionResult?>? qrDetectionsNotifier;
  final GestureLongPressStartCallback? onTextSelectionStart;
  final bool isActive;
  final int? itemIndex;
  final ValueListenable<int>? activeItemIndexListenable;

  const ZoomableLiveImageNew(
    this.enteFile, {
    super.key,
    this.shouldDisableScroll,
    required this.tagPrefix,
    this.backgroundDecoration,
    this.isFromMemories = false,
    this.onFinalFileLoad,
    this.onFinalImageLoaded,
    this.qrDetectionsNotifier,
    this.onTextSelectionStart,
    this.isActive = true,
    this.itemIndex,
    this.activeItemIndexListenable,
  });

  @override
  State<ZoomableLiveImageNew> createState() => _ZoomableLiveImageNewState();
}

class _ZoomableLiveImageNewState extends State<ZoomableLiveImageNew>
    with SingleTickerProviderStateMixin {
  final Logger _logger = Logger("ZoomableLiveImageNew");
  late EnteFile _enteFile;
  late final LiveImageLongPressRouter _longPressRouter;
  bool _showVideo = false;
  bool _isVideoFrameReady = true;
  Future<MotionPhotoAvailability>? _videoLoad;

  late final _player = Player();
  VideoController? _videoController;

  bool isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;

  @override
  void initState() {
    super.initState();

    _enteFile = widget.enteFile;
    _longPressRouter = LiveImageLongPressRouter(
      motionVideoIndex: _enteFile.pubMagicMetadata?.mvi,
      probeMotionPhoto: _loadLiveVideo,
    );
    _logger.info(
      'initState for ${_enteFile.generatedID} with tag ${_enteFile.tag} and name ${_enteFile.displayName}',
    );
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      setState(() {
        isGuestView = event.isGuestView;
      });
    });
  }

  bool _isPositionInQrRegion(Offset localPosition) {
    final detections = widget.qrDetectionsNotifier?.value?.forFile(
      widget.enteFile,
    );
    if (detections == null || detections.isEmpty) return false;
    final file = widget.enteFile;
    if (!file.hasDimensions) return false;

    final size = context.size;
    if (size == null) return false;

    final imageAspect = file.width / file.height;
    final widgetAspect = size.width / size.height;

    double displayW, displayH;
    if (imageAspect > widgetAspect) {
      displayW = size.width;
      displayH = size.width / imageAspect;
    } else {
      displayH = size.height;
      displayW = size.height * imageAspect;
    }

    final offsetX = (size.width - displayW) / 2;
    final offsetY = (size.height - displayH) / 2;

    final normX = (localPosition.dx - offsetX) / displayW;
    final normY = (localPosition.dy - offsetY) / displayH;

    for (final d in detections) {
      if (normX >= d.x &&
          normX <= d.x + d.width &&
          normY >= d.y &&
          normY <= d.y + d.height) {
        return true;
      }
    }
    return false;
  }

  bool _isLongPressInVisibleQrRegion(Offset localPosition) {
    final isQrOverlayVisible =
        !(InheritedDetailPageState.maybeOf(
              context,
            )?.enableFullScreenNotifier.value ??
            true);
    return isQrOverlayVisible && _isPositionInQrRegion(localPosition);
  }

  void _setPlaybackPressed(bool isPressed) {
    if (!isPressed) {
      _videoController?.player.pause().ignore();
    }
    if (mounted) {
      setState(() {
        _showVideo = isPressed;
      });
    }
  }

  void _playOrLoadVideo() {
    if (!_showVideo) return;
    if (_videoController == null) {
      unawaited(_loadLiveVideo());
      return;
    }
    _videoController!.player.seek(Duration.zero).ignore();
    _videoController!.player.play().ignore();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_isLongPressInVisibleQrRegion(details.localPosition)) return;

    final onTextSelectionStart = widget.onTextSelectionStart;
    if (onTextSelectionStart == null || _enteFile.isLivePhoto) {
      _setPlaybackPressed(true);
      _playOrLoadVideo();
      return;
    }

    _setPlaybackPressed(true);
    unawaited(_routeLongPress(details, onTextSelectionStart));
  }

  Future<void> _routeLongPress(
    LongPressStartDetails details,
    GestureLongPressStartCallback onTextSelectionStart,
  ) async {
    var action = LiveImageLongPressAction.textSelection;
    try {
      action = await _longPressRouter.resolve();
    } catch (error, stackTrace) {
      _logger.warning("Motion photo probe failed", error, stackTrace);
    }
    if (!mounted) return;
    if (action == LiveImageLongPressAction.playback) {
      _playOrLoadVideo();
    } else {
      _setPlaybackPressed(false);
      onTextSelectionStart(details);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = ZoomableImage(
      _enteFile,
      tagPrefix: widget.tagPrefix,
      shouldDisableScroll: widget.shouldDisableScroll,
      backgroundDecoration: widget.backgroundDecoration,
      isGuestView: isGuestView,
      isFromMemories: widget.isFromMemories,
      onFinalFileLoad: widget.onFinalFileLoad,
      onFinalImageLoaded: widget.onFinalImageLoaded,
      isActive: widget.isActive,
      itemIndex: widget.itemIndex,
      activeItemIndexListenable: widget.activeItemIndexListenable,
    );

    final shouldShowVideo =
        _showVideo && _videoController != null && _isVideoFrameReady;

    final Widget content = Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (_videoController != null)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            opacity: shouldShowVideo ? 1 : 0,
            child: IgnorePointer(
              ignoring: !shouldShowVideo,
              child: _getVideoPlayer(),
            ),
          ),
      ],
    );

    if (!widget.isFromMemories) {
      return GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: (_) => _setPlaybackPressed(false),
        child: content,
      );
    }
    return content;
  }

  @override
  void dispose() {
    if (_videoController != null) {
      _videoController!.player.stop();
      _videoController!.player.dispose();
    }
    _guestViewEventSubscription.cancel();
    super.dispose();
  }

  Widget _getVideoPlayer() {
    return Container(
      color: Colors.black,
      child: Video(controller: _videoController!, controls: null),
    );
  }

  Future<MotionPhotoAvailability> _loadLiveVideo() {
    if (_videoController != null) {
      return Future.value(MotionPhotoAvailability.present);
    }
    final activeLoad = _videoLoad;
    if (activeLoad != null) return activeLoad;

    late final Future<MotionPhotoAvailability> load;
    load = _loadLiveVideoOnce().whenComplete(() {
      if (identical(_videoLoad, load)) {
        _videoLoad = null;
      }
    });
    _videoLoad = load;
    return load;
  }

  Future<MotionPhotoAvailability> _loadLiveVideoOnce() async {
    // Older and desktop uploads can be motion photos without the live-photo
    // file type.
    final _MotionPhotoVideoResult result;
    if (_enteFile.isLivePhoto) {
      result = _MotionPhotoVideoResult(
        MotionPhotoAvailability.present,
        await _getLivePhotoVideo(),
      );
    } else {
      result = await _getMotionPhotoVideo();
    }

    if (!mounted) return result.availability;
    final videoFile = result.videoFile;
    if (videoFile != null && videoFile.existsSync()) {
      await _setVideoController(videoFile.path);
    } else if (_enteFile.isLivePhoto) {
      showShortToast(context, context.strings.downloadFailed);
    }
    return result.availability;
  }

  Future<File?> _getLivePhotoVideo() async {
    if (_enteFile.isRemoteOnlyFile &&
        !(await isFileCached(_enteFile, liveVideo: true))) {
      if (!mounted) return null;
      showShortToast(context, context.strings.downloading);
    }

    File? videoFile = await getFile(widget.enteFile, liveVideo: true)
        .timeout(const Duration(seconds: 15))
        .onError((dynamic e, s) {
          _logger.info("getFile failed ${_enteFile.tag}", e);
          return null;
        });

    // FixMe: Here, we are fetching video directly when getFile failed
    // getFile with liveVideo as true can fail for file with localID when
    // the live photo was downloaded from remote.
    if ((videoFile == null || !videoFile.existsSync()) &&
        _enteFile.uploadedFileID != null) {
      videoFile = await getFileFromServer(widget.enteFile, liveVideo: true)
          .timeout(const Duration(seconds: 15))
          .onError((dynamic e, s) {
            _logger.info("getRemoteFile failed ${_enteFile.tag}", e);
            return null;
          });
    }
    return videoFile;
  }

  Future<_MotionPhotoVideoResult> _getMotionPhotoVideo() async {
    if (_enteFile.isRemoteOnlyFile && !(await isFileCached(_enteFile))) {
      if (!mounted) {
        return const _MotionPhotoVideoResult(
          MotionPhotoAvailability.unknown,
          null,
        );
      }
      showShortToast(context, context.strings.downloading);
    }

    final File? imageFile =
        await getFile(
          widget.enteFile,
          isOrigin: !Platform.isAndroid,
        ).timeout(const Duration(seconds: 15)).onError((dynamic e, s) {
          _logger.info("getFile failed ${_enteFile.tag}", e);
          return null;
        });
    if (imageFile != null) {
      final index = await getMotionVideoIndex(filePath: imageFile.path);
      if (index != null) {
        if (!_enteFile.isMotionPhoto && _enteFile.canEditMetaInfo) {
          FileMagicService.instance
              .updatePublicMagicMetadata(
                [_enteFile],
                {motionVideoIndexKey: index.start.toInt()},
              )
              .ignore();
        }
        final outputPath = await extractMotionVideoFile(
          filePath: imageFile.path,
          destinationDirectory: (await getTemporaryDirectory()).path,
          index: index,
        );
        if (outputPath != null) {
          return _MotionPhotoVideoResult(
            MotionPhotoAvailability.present,
            File(outputPath),
          );
        }
        return const _MotionPhotoVideoResult(
          MotionPhotoAvailability.present,
          null,
        );
      } else if (_enteFile.isMotionPhoto && _enteFile.canEditMetaInfo) {
        _logger.info('Incorrectly tagged as MP, reset tag ${_enteFile.tag}');
        FileMagicService.instance
            .updatePublicMagicMetadata([_enteFile], {motionVideoIndexKey: 0})
            .ignore();
      }
      return const _MotionPhotoVideoResult(
        MotionPhotoAvailability.absent,
        null,
      );
    }
    return const _MotionPhotoVideoResult(MotionPhotoAvailability.unknown, null);
  }

  Future<void> _setVideoController(String url) async {
    if (!mounted) return;

    final controller = VideoController(_player);
    setState(() {
      _videoController = controller;
      _isVideoFrameReady = false;
    });

    try {
      await _player.setPlaylistMode(PlaylistMode.single);
      await _player.open(Media(url), play: true);
    } catch (e, s) {
      _logger.info(
        "Failed to initialize live photo video ${_enteFile.tag}",
        e,
        s,
      );
      if (!mounted || _videoController != controller) return;
      setState(() {
        _videoController = null;
        _isVideoFrameReady = false;
      });
      return;
    }

    if (!_showVideo) {
      await _player.pause();
    }

    try {
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 2),
      );
    } catch (e, s) {
      _logger.info("First frame wait failed for ${_enteFile.tag}", e, s);
    }

    if (_showVideo) {
      await _player.seek(Duration.zero);
      await _player.play();
    }

    if (!mounted || _videoController != controller) return;
    setState(() {
      _isVideoFrameReady = true;
    });
  }
}

class _MotionPhotoVideoResult {
  final MotionPhotoAvailability availability;
  final File? videoFile;

  const _MotionPhotoVideoResult(this.availability, this.videoFile);
}
