import "dart:async";
import "dart:io";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/events/resume_video_event.dart";
import "package:photos/events/stream_switched_event.dart";
import "package:photos/events/video_mute_changed_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import 'package:photos/module/download/download_error.dart';
import "package:photos/module/download/file.dart";
import "package:photos/module/download/progressive_video_stream.dart";
import "package:photos/module/download/task.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/files_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_download_progress_indicator.dart";
import "package:photos/ui/viewer/file/video_widget_media_kit_common.dart"
    as common;
import "package:photos/utils/dialog_util.dart";

class VideoWidgetMediaKit extends StatefulWidget {
  final EnteFile file;
  final String? tagPrefix;
  final FullScreenRequestCallback? playbackCallback;
  final Function(bool)? shouldDisableScroll;
  final bool isFromMemories;
  final bool isActive;
  final bool? isAudioMutedOverride;
  final File? preview;
  final bool selectedPreview;
  final ValueNotifier<double> playbackSpeed;
  final Function({required int memoryDuration})? onFinalFileLoad;

  const VideoWidgetMediaKit(
    this.file, {
    this.tagPrefix,
    this.playbackCallback,
    this.shouldDisableScroll,
    this.isFromMemories = false,
    required this.isActive,
    this.isAudioMutedOverride,
    this.preview,
    required this.selectedPreview,
    required this.playbackSpeed,
    this.onFinalFileLoad,
    super.key,
  });

  @override
  State<VideoWidgetMediaKit> createState() => _VideoWidgetMediaKitState();
}

class _VideoWidgetMediaKitState extends State<VideoWidgetMediaKit>
    with WidgetsBindingObserver {
  final Logger _logger = Logger("VideoWidgetMediaKitNew");
  late final player = Player();
  VideoController? controller;
  final _progressNotifier = ValueNotifier<double?>(null);
  bool _isAppInFG = true;
  late StreamSubscription<PauseVideoEvent> pauseVideoSubscription;
  late StreamSubscription<ResumeVideoEvent> resumeVideoSubscription;
  StreamSubscription<VideoMuteChangedEvent>? _muteSubscription;
  bool isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  bool _isGuestView = false;
  StreamSubscription<StreamSwitchedEvent>? _streamSwitchedSubscription;
  StreamSubscription<DownloadTask>? _downloadTaskSubscription;
  ProgressiveVideoStream? _progressive;
  Future<void>? _progressiveCleanup;
  int _videoLoad = 0;
  String? _loadedSource;
  StreamSubscription<String>? _playerErrors;
  final _transformationController = TransformationController();
  bool _isZooming = false;

  @override
  void initState() {
    _logger.info(
      'initState for ${widget.file.generatedID} with tag ${widget.file.tag} and name ${widget.file.displayName}',
    );
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.selectedPreview) {
      loadPreview();
    } else {
      loadOriginal();
    }

    pauseVideoSubscription = Bus.instance.on<PauseVideoEvent>().listen((event) {
      if (event.fileTag != null && event.fileTag != widget.file.tag) return;
      player.pause();
    });
    resumeVideoSubscription = Bus.instance.on<ResumeVideoEvent>().listen((
      event,
    ) {
      if (widget.isActive) player.play();
    });
    if (!widget.isFromMemories) {
      _muteSubscription = Bus.instance.on<VideoMuteChangedEvent>().listen((
        event,
      ) {
        player.setVolume(event.isMuted ? 0.0 : 100.0);
      });
    }
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      setState(() {
        _isGuestView = event.isGuestView;
      });
    });
    if (widget.file.isUploaded) {
      _downloadTaskSubscription = downloadManager
          .watchDownload(widget.file.uploadedFileID!)
          .listen((event) {
            if (mounted) {
              setState(() {
                _progressNotifier.value = event.progress;
              });
            }
          });
    }

    _streamSwitchedSubscription = Bus.instance.on<StreamSwitchedEvent>().listen(
      (event) {
        if (event.fileTag != widget.file.tag ||
            event.type != PlayerType.mediaKit ||
            !mounted) {
          return;
        }
        if (event.selectedPreview) {
          loadPreview();
        } else {
          loadOriginal();
        }
      },
    );

    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.videoPlayback,
    );
  }

  @override
  void didUpdateWidget(covariant VideoWidgetMediaKit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      widget.isActive ? player.play() : player.pause();
    }
    if (oldWidget.isAudioMutedOverride != widget.isAudioMutedOverride) {
      _applyVolume();
    }
  }

  void loadPreview() async {
    final generation = ++_videoLoad;
    final cleanup = _disposeProgressive();
    if (cleanup != null) {
      await cleanup;
      if (!mounted || generation != _videoLoad) {
        return;
      }
    }
    final preview = widget.preview;
    if (preview == null) return;
    _setVideoController(preview.path);
  }

  void loadOriginal() async {
    final generation = ++_videoLoad;
    final cleanup = _disposeProgressive();
    if (cleanup != null) {
      await cleanup;
      if (!mounted || generation != _videoLoad) {
        return;
      }
    }
    if (widget.file.isRemoteOnlyFile) {
      _loadNetworkVideo();
      _setFileSizeIfNull();
    } else if (widget.file.isSharedMediaToAppSandbox) {
      final localFile = File(getSharedMediaFilePath(widget.file));
      if (localFile.existsSync()) {
        _setVideoController(localFile.path);
      } else if (widget.file.uploadedFileID != null) {
        _loadNetworkVideo();
      }
    } else {
      await widget.file.getAsset.then((asset) async {
        // Android trash assets may report that they do not exist.
        final exists = await asset?.exists ?? false;
        if (!mounted || generation != _videoLoad) {
          return;
        }
        if (asset == null || !(exists || widget.file.isDeviceTrash)) {
          if (widget.file.uploadedFileID != null) {
            _loadNetworkVideo();
          }
        } else {
          // ignore: unawaited_futures
          asset.getMediaUrl().then((url) {
            if (!mounted || generation != _videoLoad) {
              return;
            }
            _setVideoController(
              url ??
                  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
            );
          });
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInFG = true;
    } else {
      _isAppInFG = false;
    }
  }

  @override
  void dispose() {
    _videoLoad++;
    _progressive?.dispose().ignore();
    _progressive = null;
    _playerErrors?.cancel();
    _streamSwitchedSubscription?.cancel();
    _guestViewEventSubscription.cancel();
    pauseVideoSubscription.cancel();
    resumeVideoSubscription.cancel();
    _muteSubscription?.cancel();
    removeDownloadCallback(widget.file);
    _progressNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_downloadTaskSubscription != null) {
      _downloadTaskSubscription!.cancel();
      downloadManager.pause(widget.file.uploadedFileID!).ignore();
    }
    player.dispose();
    _transformationController.dispose();
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.videoPlayback,
    );
    super.dispose();
  }

  void _onInteractionLockChanged(bool shouldLock) {
    if (_isZooming != shouldLock) {
      setState(() {
        _isZooming = shouldLock;
      });
    }
    widget.shouldDisableScroll?.call(shouldLock);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // During zoom, keep this recognizer out of multi-touch gesture arenas.
      onVerticalDragUpdate: _isGuestView || _isZooming
          ? null
          : (d) {
              if (d.delta.dy > dragSensitivity) {
                Navigator.of(context).pop();
              } else if (d.delta.dy < (dragSensitivity * -1)) {
                showDetailsSheet(context, widget.file);
              }
            },
      child: Center(
        child: controller != null && _loadedSource != null
            ? common.VideoWidget(
                widget.file,
                controller!,
                widget.playbackCallback,
                transformationController: _transformationController,
                onInteractionLockChanged: _onInteractionLockChanged,
                isFromMemories: widget.isFromMemories,
                isPreviewPlayer: widget.selectedPreview,
                playbackSpeed: widget.playbackSpeed,
              )
            : Center(
                child: ValueListenableBuilder(
                  valueListenable: _progressNotifier,
                  builder: (BuildContext context, double? progress, _) {
                    return VideoDownloadProgressIndicator(progress: progress);
                  },
                ),
              ),
      ),
    );
  }

  Future<void>? _disposeProgressive() {
    final stream = _progressive;
    _progressive = null;
    if (stream == null) {
      return _progressiveCleanup;
    }
    return _progressiveCleanup = player
        .stop()
        .catchError((Object _) {})
        .whenComplete(stream.dispose);
  }

  void _loadNetworkVideo() {
    if (flagService.progressiveOriginalVideoPlayback) {
      unawaited(_loadProgressively());
    } else {
      _loadNetworkVideoFully();
    }
  }

  Future<void> _loadProgressively() async {
    final generation = _videoLoad;
    bool isCurrent() => mounted && generation == _videoLoad;
    final stream = ProgressiveVideoStream(
      widget.file,
      onProgress: (count, total) {
        if (isCurrent()) {
          _progressNotifier.value = count / total;
        }
      },
    );
    _progressive = stream;
    try {
      final url = await stream.open();
      if (!isCurrent()) {
        return;
      }
      if (url != null) {
        _playerErrors ??= player.stream.error.listen((_) {
          final stream = _progressive;
          if (stream != null &&
              stream.url != null &&
              stream.url == _loadedSource) {
            stream.playbackFailed();
          }
        });
        _setVideoController(url);
        await stream.failure;
        return;
      }
    } catch (error) {
      if (isCurrent()) {
        _logger.info('Progressive playback unavailable (${error.runtimeType})');
      }
    }
    if (!isCurrent()) {
      return;
    }
    setState(() => _loadedSource = null);
    await _disposeProgressive();
    if (!isCurrent()) {
      return;
    }
    _loadNetworkVideoFully(generation: generation);
  }

  void _loadNetworkVideoFully({int? generation}) {
    bool isCurrent() =>
        mounted && (generation == null || generation == _videoLoad);
    getFileFromServer(
          widget.file,
          throwOnDecryptionFailure: true,
          progressCallback: (count, total) {
            if (!isCurrent()) {
              return;
            }
            _progressNotifier.value = count / (widget.file.fileSize ?? total);
            if (_progressNotifier.value == 1) {
              if (mounted) {
                showShortToast(context, context.strings.decryptingVideo);
              }
            }
          },
        )
        .then((file) {
          if (file != null && isCurrent()) {
            _setVideoController(file.path);
          }
        })
        .onError((error, stackTrace) {
          if (!mounted || !isCurrent()) {
            return;
          }
          if (error is DownloadDecryptionError) {
            showDownloadDecryptionFailedDialog(context: context);
          } else {
            showErrorDialog(
              context,
              context.strings.error,
              context.strings.failedToDownloadVideo,
            );
          }
        });
  }

  void _setFileSizeIfNull() {
    if (widget.file.fileSize == null && widget.file.canEditMetaInfo) {
      FilesService.instance.getFileSize(widget.file.uploadedFileID!).then((
        value,
      ) {
        widget.file.fileSize = value;
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  void _setVideoController(String url) {
    if (mounted) {
      setState(() {
        if (controller == null) {
          player.setPlaylistMode(
            localSettings.shouldLoopVideo()
                ? PlaylistMode.single
                : PlaylistMode.none,
          );
          controller = VideoController(player);
        }
        _applyVolume();
        _loadedSource = url;
        final stream = _progressive?.url == url ? _progressive : null;
        player.open(Media(url), play: _isAppInFG && widget.isActive).catchError(
          (Object error, StackTrace stack) {
            if (stream == null) {
              Error.throwWithStackTrace(error, stack);
            }
            stream.playbackFailed();
          },
        );
      });
      int duration = controller!.player.state.duration.inSeconds;
      if (duration == 0) {
        duration = 10;
      }
      widget.onFinalFileLoad?.call(memoryDuration: duration);
    }
  }

  void _applyVolume() {
    final mutedOverride = widget.isAudioMutedOverride;
    if (mutedOverride != null) {
      player.setVolume(mutedOverride ? 0.0 : 100.0);
    } else if (!widget.isFromMemories) {
      player.setVolume(localSettings.isMuted() ? 0.0 : 100.0);
    }
  }
}
