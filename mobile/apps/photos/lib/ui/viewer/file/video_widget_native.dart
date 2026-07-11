import "dart:async";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:native_video_player/native_video_player.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/file_caption_updated_event.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/events/resume_video_event.dart";
import "package:photos/events/seekbar_triggered_event.dart";
import "package:photos/events/stream_switched_event.dart";
import "package:photos/events/use_media_kit_for_video.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/preview/playlist_data.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/task.dart";
import "package:photos/module/metadata/video.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/files_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/native_video_player_controls/play_pause_button.dart";
import "package:photos/ui/viewer/file/native_video_player_controls/seek_bar.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/file/video_stream_change.dart";
import "package:photos/ui/viewer/file/zoomable_video_viewer.dart";
import "package:photos/utils/dialog_util.dart";
import "package:video_player/video_player.dart" as vp;
import "package:visibility_detector/visibility_detector.dart";

class VideoWidgetNative extends StatefulWidget {
  final EnteFile file;
  final String? tagPrefix;
  final FullScreenRequestCallback? playbackCallback;
  final Function(bool)? shouldDisableScroll;
  final bool isFromMemories;
  final void Function()? onStreamChange;
  final PlaylistData? playlistData;
  final bool selectedPreview;
  final Function({required int memoryDuration})? onFinalFileLoad;

  const VideoWidgetNative(
    this.file, {
    this.tagPrefix,
    this.playbackCallback,
    this.shouldDisableScroll,
    this.isFromMemories = false,
    required this.onStreamChange,
    super.key,
    this.playlistData,
    this.onFinalFileLoad,
    required this.selectedPreview,
  });

  @override
  State<VideoWidgetNative> createState() => _VideoWidgetNativeState();
}

class _VideoWidgetNativeState extends State<VideoWidgetNative>
    with WidgetsBindingObserver {
  final Logger _logger = Logger("VideoWidgetNative");
  static const verticalMargin = 64.0;
  final _progressNotifier = ValueNotifier<double?>(null);
  late StreamSubscription<PauseVideoEvent> pauseVideoSubscription;
  late StreamSubscription<ResumeVideoEvent> resumeVideoSubscription;
  bool _isGuestView = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  NativeVideoPlayerController? _controller;
  String? _filePath;
  String? duration;
  double? aspectRatio;
  final _isPlaybackReady = ValueNotifier(false);
  bool _shouldClearCache = false;
  bool _isCompletelyVisible = false;
  final _showControls = ValueNotifier(true);
  final _isSeeking = ValueNotifier(false);
  final _debouncer = Debouncer(const Duration(milliseconds: 2000));
  StreamSubscription<PlaybackEvent>? _subscription;
  StreamSubscription<StreamSwitchedEvent>? _streamSwitchedSubscription;
  StreamSubscription<DownloadTask>? downloadTaskSubscription;
  late final StreamSubscription<FileCaptionUpdatedEvent>
  _captionUpdatedSubscription;
  int position = 0;
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
      _controller?.pause();
    });
    resumeVideoSubscription = Bus.instance.on<ResumeVideoEvent>().listen((
      event,
    ) {
      _controller?.play();
    });
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      if (!mounted) return;
      setState(() {
        _isGuestView = event.isGuestView;
      });
    });
    _streamSwitchedSubscription = Bus.instance.on<StreamSwitchedEvent>().listen(
      (event) {
        if (event.type != PlayerType.nativeVideoPlayer) return;
        _filePath = null;
        if (event.selectedPreview) {
          loadPreview(update: true);
        } else {
          loadOriginal(update: true);
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
    if (widget.file.isUploaded) {
      downloadTaskSubscription = downloadManager
          .watchDownload(widget.file.uploadedFileID!)
          .listen((event) {
            _progressNotifier.value = event.progress;
          });
    }

    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.videoPlayback,
    );
  }

  Future<void> setVideoSource() async {
    if (_filePath == null) {
      _logger.info('Stop video player, file path is null');
      await _controller?.stop();
      return;
    }
    final videoSource = VideoSource(
      path: _filePath!,
      type: VideoSourceType.file,
    );
    await _controller?.loadVideo(videoSource);
    await _controller?.play();

    Bus.instance.fire(SeekbarTriggeredEvent(position: 0));
  }

  void loadPreview({bool update = false}) async {
    final previewPath = widget.playlistData?.preview.path;
    if (previewPath == null) {
      loadOriginal(update: true);
      return;
    }
    _setFilePathForNativePlayer(previewPath, update);

    await setVideoSource();
  }

  void loadOriginal({bool update = false}) async {
    if (widget.file.isRemoteOnlyFile) {
      _loadNetworkVideo(update);
      _setFileSizeIfNull();
    } else if (widget.file.isSharedMediaToAppSandbox) {
      final localFile = File(getSharedMediaFilePath(widget.file));
      if (localFile.existsSync()) {
        _setFilePathForNativePlayer(localFile.path, update);
      } else if (widget.file.uploadedFileID != null) {
        _loadNetworkVideo(update);
      }
    } else {
      await widget.file.getAsset.then((asset) async {
        if (asset == null || !(await asset.exists)) {
          if (widget.file.uploadedFileID != null) {
            _loadNetworkVideo(update);
          }
        } else {
          // ignore: unawaited_futures
          getFile(widget.file, isOrigin: true).then((file) {
            if (file == null) {
              _loadNetworkVideo(update);
              return;
            }
            _setFilePathForNativePlayer(file.path, update);
            if (Platform.isIOS) {
              _shouldClearCache = true;
            }
          });
        }
      });
    }
    if (update) {
      await setVideoSource();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (_controller?.playbackStatus == PlaybackStatus.playing) {
        _controller?.pause();
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller?.stop().ignore();
    _controller?.dispose();
    if (downloadTaskSubscription != null) {
      downloadTaskSubscription!.cancel();
      downloadManager.pause(widget.file.uploadedFileID!).ignore();
    }

    //https://github.com/fluttercandies/flutter_photo_manager/blob/8afba2745ebaac6af8af75de9cbded9157bc2690/README.md#clear-caches
    if (_shouldClearCache) {
      _logger.info("Clearing cache");
      final file = File(_filePath!);

      /// Checking if exists to avoid observed PathNotFoundException. Didn't find
      /// root cause.
      if (file.existsSync()) {
        file.delete().then((value) {
          _logger.info("Cache cleared");
        });
      }
    }
    _streamSwitchedSubscription?.cancel();
    _guestViewEventSubscription.cancel();
    pauseVideoSubscription.cancel();
    resumeVideoSubscription.cancel();
    removeDownloadCallback(widget.file);
    _progressNotifier.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _isPlaybackReady.dispose();
    _showControls.dispose();
    _isSeeking.removeListener(_seekListener);
    _isSeeking.dispose();
    _debouncer.cancelDebounceTimer();
    _captionUpdatedSubscription.cancel();
    _transformationController.dispose();
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.videoPlayback,
    );
    super.dispose();
  }

  void _onInteractionLockChanged(bool shouldLock) {
    if (!mounted) return;
    if (_isZooming != shouldLock) {
      setState(() {
        _isZooming = shouldLock;
      });
    }
    widget.shouldDisableScroll?.call(shouldLock);
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.tagPrefix! + widget.file.tag,
      child: VisibilityDetector(
        key: Key(widget.file.generatedID.toString()),
        onVisibilityChanged: (info) {
          if (info.visibleFraction == 1) {
            setState(() {
              _isCompletelyVisible = true;
            });
          }
        },
        child: GestureDetector(
          // Keep recognizer out of the arena during multi-touch/zoom to avoid
          // it stealing pinch gestures with predominantly vertical movement.
          onVerticalDragUpdate: _isGuestView || _isZooming
              ? null
              : (d) {
                  if (d.delta.dy > dragSensitivity) {
                    _stopPlaybackBeforeDismiss();
                    Navigator.of(context).pop();
                  } else if (d.delta.dy < (dragSensitivity * -1)) {
                    showDetailsSheet(context, widget.file);
                  }
                },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 750),
            switchOutCurve: Curves.easeOutExpo,
            switchInCurve: Curves.easeInExpo,
            //Loading two high-res potrait videos together causes one to
            //go blank. So only loading video when it is completely visible.
            child: !_isCompletelyVisible || _filePath == null
                ? _getLoadingWidget()
                : Stack(
                    key: const ValueKey("video_ready"),
                    children: [
                      ZoomableVideoViewer(
                        transformationController: _transformationController,
                        onInteractionLockChanged: _onInteractionLockChanged,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: aspectRatio ?? 1,
                            child: NativeVideoPlayerView(
                              onViewReady: _initializeController,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: widget.isFromMemories
                            ? null
                            : () {
                                _showControls.value = !_showControls.value;
                                if (widget.playbackCallback != null) {
                                  widget.playbackCallback!(
                                    !_showControls.value,
                                    FullScreenRequestReason.userInteraction,
                                  );
                                }
                              },
                        onLongPress: () {
                          if (widget.isFromMemories) {
                            widget.playbackCallback?.call(
                              false,
                              FullScreenRequestReason.userInteraction,
                            );
                            _controller?.pause();
                          }
                        },
                        onLongPressUp: () {
                          if (widget.isFromMemories) {
                            widget.playbackCallback?.call(
                              true,
                              FullScreenRequestReason.userInteraction,
                            );
                            _controller?.play();
                          }
                        },
                        child: Container(
                          constraints: const BoxConstraints.expand(),
                        ),
                      ),
                      widget.isFromMemories
                          ? const SizedBox.shrink()
                          : Positioned.fill(
                              child: Center(
                                child: ValueListenableBuilder(
                                  builder:
                                      (BuildContext context, bool value, _) {
                                        return value
                                            ? ValueListenableBuilder(
                                                builder:
                                                    (context, bool value, _) {
                                                      return AnimatedOpacity(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 200,
                                                            ),
                                                        opacity: value ? 1 : 0,
                                                        curve: Curves
                                                            .easeInOutQuad,
                                                        child: IgnorePointer(
                                                          ignoring: !value,
                                                          child:
                                                              PlayPauseButton(
                                                                _controller,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                valueListenable: _showControls,
                                              )
                                            : const SizedBox();
                                      },
                                  valueListenable: _isPlaybackReady,
                                ),
                              ),
                            ),
                      widget.isFromMemories
                          ? const SizedBox.shrink()
                          : Positioned(
                              bottom: verticalMargin,
                              right: 0,
                              left: 0,
                              child: SafeArea(
                                top: false,
                                left: false,
                                right: false,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: widget.isFromMemories ? 32 : 0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      ValueListenableBuilder(
                                        valueListenable: _showControls,
                                        builder: (context, value, _) {
                                          return VideoStreamChangeWidget(
                                            showControls: value,
                                            file: widget.file,
                                            isPreviewPlayer:
                                                widget.selectedPreview,
                                            onStreamChange:
                                                widget.onStreamChange,
                                          );
                                        },
                                      ),
                                      ValueListenableBuilder(
                                        valueListenable: _isPlaybackReady,
                                        builder:
                                            (
                                              BuildContext context,
                                              bool value,
                                              _,
                                            ) {
                                              return value
                                                  ? _SeekBarAndDuration(
                                                      controller: _controller,
                                                      duration: duration,
                                                      showControls:
                                                          _showControls,
                                                      isSeeking: _isSeeking,
                                                      position: position,
                                                      file: widget.file,
                                                    )
                                                  : const SizedBox();
                                            },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  void _stopPlaybackBeforeDismiss() {
    _controller?.pause();
    _controller?.stop().ignore();
    widget.playbackCallback?.call(
      false,
      FullScreenRequestReason.userInteraction,
    );
  }

  Future<void> _initializeController(
    NativeVideoPlayerController controller,
  ) async {
    try {
      _logger.info(
        "Initializing native video player controller for file gen id: ${widget.file.generatedID}",
      );
      _controller = controller;

      _subscription = controller.events.listen(_listen);

      _isSeeking.addListener(_seekListener);

      await setVideoSource();
    } catch (e) {
      _logger.severe(
        "Error initializing native video player controller for file gen id: ${widget.file.generatedID}",
        e,
      );
    }
  }

  void _listen(PlaybackEvent event) {
    switch (event) {
      case PlaybackStatusChangedEvent():
        _onPlaybackStatusChanged();
      case PlaybackReadyEvent():
        _onPlaybackReady();
        break;
      case PlaybackPositionChangedEvent():
        position = event.positionInMilliseconds;
        if (mounted) {
          setState(() {});
        }
        break;
      case PlaybackEndedEvent():
        _onPlaybackEnded();
        break;
      case PlaybackErrorEvent():
        _onError(event.errorMessage);
        break;
      default:
    }
  }

  void _seekListener() {
    if (widget.isFromMemories) return;
    if (!_isSeeking.value &&
        _controller?.playbackStatus == PlaybackStatus.playing) {
      _debouncer.run(() async {
        if (mounted) {
          if (_isSeeking.value ||
              _controller?.playbackStatus != PlaybackStatus.playing) {
            return;
          }
          _showControls.value = false;
          if (widget.playbackCallback != null) {
            widget.playbackCallback!(
              true,
              FullScreenRequestReason.playbackStateChange,
            );
          }
        }
      });
    }
  }

  void _onPlaybackStatusChanged() {
    if (widget.isFromMemories) return;
    final duration = widget.file.duration != null
        ? widget.file.duration! * 1000
        : _controller?.videoInfo?.durationInMilliseconds;

    if (_isSeeking.value ||
        _controller?.playbackPosition.inMilliseconds == duration) {
      return;
    }
    if (_controller!.playbackStatus == PlaybackStatus.playing) {
      if (mounted) {
        _debouncer.run(() async {
          if (mounted) {
            if (_isSeeking.value ||
                _controller!.playbackStatus != PlaybackStatus.playing) {
              return;
            }
            _showControls.value = false;
            if (widget.playbackCallback != null) {
              widget.playbackCallback!(
                true,
                FullScreenRequestReason.playbackStateChange,
              );
            }
          }
        });
      }
    } else {
      if (widget.playbackCallback != null && mounted) {
        widget.playbackCallback!(
          false,
          FullScreenRequestReason.playbackStateChange,
        );
      }
    }

    _handleWakeLockOnPlaybackChanges();
  }

  void _onError(String errorMessage) {
    //This doesn't work all the time
    _logger.severe(
      "Error in native video player controller for file gen id: ${widget.file.generatedID}",
    );
    _logger.severe(errorMessage);
    Bus.instance.fire(UseMediaKitForVideo());
  }

  Future<void> _onPlaybackReady() async {
    if (_isPlaybackReady.value) return;
    await _controller!.play();
    final durationInSeconds = durationToSeconds(duration) ?? 10;
    widget.onFinalFileLoad?.call(memoryDuration: durationInSeconds);
    unawaited(_controller!.setVolume(1));
    _isPlaybackReady.value = true;
  }

  void _onPlaybackEnded() async {
    await _controller?.stop();
    if (localSettings.shouldLoopVideo()) {
      Bus.instance.fire(SeekbarTriggeredEvent(position: 0));
      await _controller?.play();
    }
  }

  void _loadNetworkVideo(bool update) {
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
            _setFilePathForNativePlayer(file.path, update);
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

  void _handleWakeLockOnPlaybackChanges() {
    final playbackStatus = _controller?.playbackStatus;
    if (playbackStatus == PlaybackStatus.playing) {
      wakeLockService.updateWakeLock(
        enable: true,
        wakeLockFor: WakeLockFor.videoPlayback,
      );
    } else {
      wakeLockService.updateWakeLock(
        enable: false,
        wakeLockFor: WakeLockFor.videoPlayback,
      );
    }
  }

  Widget _getLoadingWidget() {
    return Stack(
      key: const ValueKey("video_loading"),
      children: [
        Container(
          color: Colors.black,
          constraints: const BoxConstraints.expand(),
          child: _getThumbnail(),
        ),
        Container(
          color: Colors.black.withValues(alpha: 0.3),
          constraints: const BoxConstraints.expand(),
        ),
        Center(
          child: Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.black.withValues(alpha: 0.3),
              border: Border.all(color: strokeFaintDark, width: 1),
            ),
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
      ],
    );
  }

  Widget _getThumbnail() {
    return ThumbnailWidget(
      widget.file,
      fit: BoxFit.contain,
      shouldShowVideoOverlayIcon: false,
      rawThumbnail: true,
    );
  }

  void _setFilePathForNativePlayer(String url, bool update) {
    if (!mounted) return;
    setState(() {
      _filePath = url;
    });
    _setAspectRatioFromVideoProps().then((_) {
      if (!mounted) return;
      setState(() {});
    });

    if (update) {
      setVideoSource();
    }
  }

  Future<void> _setAspectRatioFromVideoProps() async {
    if (aspectRatio != null && duration != null) return;

    if (widget.playlistData != null && widget.selectedPreview) {
      aspectRatio = widget.playlistData!.width! / widget.playlistData!.height!;
      if (duration == "0:00" || duration == null) {
        if ((widget.file.duration ?? 0) > 0) {
          duration = secondsToDuration(widget.file.duration!);
        } else if (widget.playlistData!.durationInSeconds != null) {
          duration = secondsToDuration(widget.playlistData!.durationInSeconds!);
        }
      }
      _logger.info("Getting aspect ratio from preview video");
      return;
    }
    if (Platform.isIOS) {
      // FFprobe in ffmpeg_kit can crash on certain iOS media files.
      // On iOS, use lightweight metadata probing via AVPlayer.
      if (widget.file.hasDimensions) {
        aspectRatio = widget.file.width / widget.file.height;
      } else {
        aspectRatio ??= 1;
      }
      if ((duration == null || duration == "0:00") &&
          (widget.file.duration ?? 0) > 0) {
        duration = secondsToDuration(widget.file.duration!);
      }
      await _setAspectAndDurationFromIosPlayerProbe();
      return;
    }
    final videoProps = await getVideoProps(File(_filePath!));
    if (videoProps != null) {
      duration = videoProps.propData?["duration"];

      if (videoProps.width != null && videoProps.height != null) {
        if (videoProps.width != null && videoProps.height != 0) {
          aspectRatio = videoProps.width! / videoProps.height!;
        } else {
          _logger.info("Video props height or width is 0");
          aspectRatio = 1;
        }
      } else {
        _logger.info("Video props width and height are null");
        aspectRatio = 1;
      }
    } else {
      _logger.info("Video props are null");
      aspectRatio = 1;
    }
  }

  Future<void> _setAspectAndDurationFromIosPlayerProbe() async {
    final path = _filePath;
    if (path == null) return;
    vp.VideoPlayerController? metadataController;
    try {
      metadataController = vp.VideoPlayerController.file(File(path));
      await metadataController.initialize().timeout(const Duration(seconds: 4));
      final value = metadataController.value;
      final probeAspectRatio = value.aspectRatio;
      // Always prefer the probed aspect ratio over file metadata dimensions,
      // because AVPlayer correctly accounts for video rotation metadata.
      // Raw file width/height may not reflect rotation (e.g. a portrait video
      // stored as 1920x1080 with 90° rotation).
      if (probeAspectRatio > 0) {
        aspectRatio = probeAspectRatio;
      }
      final durationInMilliseconds = value.duration.inMilliseconds;
      if ((duration == null || duration == "0:00") &&
          durationInMilliseconds > 0) {
        duration = secondsToDuration(durationInMilliseconds ~/ 1000);
      }
    } on TimeoutException catch (e, s) {
      _logger.warning(
        "_setAspectAndDurationFromIosPlayerProbe timed out for ${widget.file.generatedID}",
        e,
        s,
      );
    } catch (e, s) {
      _logger.warning(
        "_setAspectAndDurationFromIosPlayerProbe failed for ${widget.file.generatedID}",
        e,
        s,
      );
    } finally {
      try {
        await metadataController?.dispose();
      } catch (e, s) {
        _logger.warning(
          "_setAspectAndDurationFromIosPlayerProbe dispose failed for ${widget.file.generatedID}",
          e,
          s,
        );
      }
    }
  }
}

class _SeekBarAndDuration extends StatelessWidget {
  final NativeVideoPlayerController? controller;
  final String? duration;
  final ValueNotifier<bool> showControls;
  final ValueNotifier<bool> isSeeking;
  final int position;
  final EnteFile file;

  const _SeekBarAndDuration({
    required this.controller,
    required this.duration,
    required this.showControls,
    required this.isSeeking,
    required this.position,
    required this.file,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: showControls,
      builder: (BuildContext context, bool value, _) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInQuad,
          opacity: value ? 1 : 0,
          child: IgnorePointer(
            ignoring: !value,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  border: Border.all(color: strokeFaintDark, width: 1),
                ),
                child: Column(
                  children: [
                    file.caption != null && file.caption!.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                            child: GestureDetector(
                              onTap: () {
                                showDetailsSheet(context, file);
                              },
                              child: Text(
                                file.caption!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: getEnteTextTheme(
                                  context,
                                ).mini.copyWith(color: textBaseDark),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    Row(
                      children: [
                        AnimatedSize(
                          duration: const Duration(seconds: 5),
                          curve: Curves.easeInOut,
                          child: Text(
                            secondsToDuration(position ~/ 1000),
                            style: getEnteTextTheme(
                              context,
                            ).mini.copyWith(color: textBaseDark),
                          ),
                        ),
                        Expanded(
                          child: SeekBar(
                            controller!,
                            durationToSeconds(duration),
                            isSeeking,
                          ),
                        ),
                        Text(
                          duration ?? "0:00",
                          style: getEnteTextTheme(
                            context,
                          ).mini.copyWith(color: textBaseDark),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
