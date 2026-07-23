import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:media_kit/media_kit.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/file_caption_updated_event.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/events/resume_video_event.dart";
import "package:photos/events/stream_switched_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/task.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/files_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_widget_media_kit_common.dart"
    as common;
import "package:photos/utils/dialog_util.dart";

class VideoWidgetMediaKit extends StatefulWidget {
  final EnteFile file;
  final String? tagPrefix;
  final FullScreenRequestCallback? playbackCallback;
  final Function(bool)? shouldDisableScroll;
  final bool isFromMemories;
  final void Function() onStreamChange;
  final File? preview;
  final bool selectedPreview;
  final Function({required int memoryDuration})? onFinalFileLoad;

  const VideoWidgetMediaKit(
    this.file, {
    this.tagPrefix,
    this.playbackCallback,
    this.shouldDisableScroll,
    this.isFromMemories = false,
    required this.onStreamChange,
    this.preview,
    required this.selectedPreview,
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
  bool isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  bool _isGuestView = false;
  StreamSubscription<StreamSwitchedEvent>? _streamSwitchedSubscription;
  StreamSubscription<DownloadTask>? _downloadTaskSubscription;
  late final StreamSubscription<FileCaptionUpdatedEvent>
  _captionUpdatedSubscription;
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
      player.pause();
    });
    resumeVideoSubscription = Bus.instance.on<ResumeVideoEvent>().listen((
      event,
    ) {
      player.play();
    });
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
        if (event.type != PlayerType.mediaKit || !mounted) return;
        if (event.selectedPreview) {
          loadPreview();
        } else {
          loadOriginal();
        }
      },
    );

    _captionUpdatedSubscription = Bus.instance
        .on<FileCaptionUpdatedEvent>()
        .listen((event) {
          if (event.fileGeneratedID == widget.file.generatedID) {
            if (mounted) {
              setState(() {});
            }
          }
        });
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.videoPlayback,
    );
  }

  void loadPreview() {
    _setVideoController(widget.preview!.path);
  }

  void loadOriginal() {
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
      widget.file.getAsset.then((asset) async {
        if (asset == null || !(await asset.exists)) {
          if (widget.file.uploadedFileID != null) {
            _loadNetworkVideo();
          }
        } else {
          // ignore: unawaited_futures
          asset.getMediaUrl().then((url) {
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
    _streamSwitchedSubscription?.cancel();
    _guestViewEventSubscription.cancel();
    pauseVideoSubscription.cancel();
    resumeVideoSubscription.cancel();
    removeDownloadCallback(widget.file);
    _progressNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_downloadTaskSubscription != null) {
      _downloadTaskSubscription!.cancel();
      downloadManager.pause(widget.file.uploadedFileID!).ignore();
    }
    player.dispose();
    _captionUpdatedSubscription.cancel();
    _transformationController.dispose();
    if (wakeLockService.shouldKeepAppAwakeAcrossSessions) {
      wakeLockService.updateWakeLock(
        enable: true,
        wakeLockFor: WakeLockFor.handlingMediaKitEdgeCase,
      );
    } else {
      wakeLockService.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.videoPlayback,
      );
    }
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
      // Keep recognizer out of the arena during multi-touch/zoom to avoid
      // it stealing pinch gestures with predominantly vertical movement.
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
        child: controller != null
            ? common.VideoWidget(
                widget.file,
                controller!,
                widget.playbackCallback,
                transformationController: _transformationController,
                onInteractionLockChanged: _onInteractionLockChanged,
                isFromMemories: widget.isFromMemories,
                onStreamChange: widget.onStreamChange,
                isPreviewPlayer: widget.selectedPreview,
              )
            : Center(
                child: ValueListenableBuilder(
                  valueListenable: _progressNotifier,
                  builder: (BuildContext context, double? progress, _) {
                    return progress == null || progress == 1
                        ? const EnteLoadingWidget(
                            size: 32,
                            color: fillBaseDark,
                            padding: 0,
                          )
                        : Stack(
                            children: [
                              CircularProgressIndicator(
                                backgroundColor: Colors.transparent,
                                value: progress,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color.fromRGBO(45, 194, 98, 1.0),
                                ),
                                strokeWidth: 2,
                                strokeCap: StrokeCap.round,
                              ),
                              Center(
                                child: Text(
                                  "${(progress * 100).toStringAsFixed(0)}%",
                                  style: getEnteTextTheme(
                                    context,
                                  ).tiny.copyWith(color: textBaseDark),
                                ),
                              ),
                            ],
                          );
                  },
                ),
              ),
      ),
    );
  }

  void _loadNetworkVideo() {
    getFileFromServer(
          widget.file,
          progressCallback: (count, total) {
            if (!mounted) {
              return;
            }
            _progressNotifier.value = count / (widget.file.fileSize ?? total);
            if (_progressNotifier.value == 1) {
              if (mounted) {
                showShortToast(
                  context,
                  AppLocalizations.of(context).decryptingVideo,
                );
              }
            }
          },
        )
        .then((file) {
          if (file != null) {
            _setVideoController(file.path);
          }
        })
        .onError((error, stackTrace) {
          if (!mounted) return;
          showErrorDialog(
            context,
            AppLocalizations.of(context).error,
            AppLocalizations.of(context).failedToDownloadVideo,
          );
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
        player.open(Media(url), play: _isAppInFG);
      });
      int duration = controller!.player.state.duration.inSeconds;
      if (duration == 0) {
        duration = 10;
      }
      widget.onFinalFileLoad?.call(memoryDuration: duration);
    }
  }
}
