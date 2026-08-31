import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:photos/models/file/file.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/viewer/file/video_control/gallery_video_controls.dart";
import "package:photos/ui/viewer/file/video_double_tap_seek.dart";
import "package:photos/ui/viewer/file/video_seek_controller.dart";
import "package:photos/ui/viewer/file/video_stream_change.dart";
import "package:photos/ui/viewer/file/zoomable_video_viewer.dart";

class VideoWidget extends StatefulWidget {
  final EnteFile file;
  final VideoController controller;
  final FullScreenRequestCallback? playbackCallback;
  final TransformationController? transformationController;
  final ValueChanged<bool>? onInteractionLockChanged;
  final bool isFromMemories;
  final void Function() onStreamChange;
  final bool isPreviewPlayer;
  final ValueNotifier<double> playbackSpeed;

  const VideoWidget(
    this.file,
    this.controller,
    this.playbackCallback, {
    super.key,
    this.transformationController,
    this.onInteractionLockChanged,
    required this.isFromMemories,
    // ignore: unused_element
    required this.onStreamChange,
    required this.isPreviewPlayer,
    required this.playbackSpeed,
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  final _logger = Logger("VideoWidget");
  final showControlsNotifier = ValueNotifier<bool>(true);
  final _hideControlsDebouncer = Debouncer(const Duration(milliseconds: 2000));
  late final VideoSeekController _seekController;
  bool _isSeekInteractionActive = false;
  late final StreamSubscription<bool> _isPlayingStreamSubscription;
  late final StreamSubscription<bool> _completedStreamSubscription;

  @override
  void initState() {
    super.initState();
    widget.playbackSpeed.addListener(_onPlaybackSpeedChanged);
    widget.controller.player.setRate(widget.playbackSpeed.value);
    _seekController = VideoSeekController(
      seek: widget.controller.player.seek,
      readPosition: () => widget.controller.player.state.position,
      readDuration: () => widget.controller.player.state.duration,
      onSeekError: (error, stackTrace) {
        _logger.warning("Could not seek video", error, stackTrace);
      },
    );
    _seekController.addListener(_onSeekInteractionChanged);
    _isPlayingStreamSubscription = widget.controller.player.stream.playing
        .listen((isPlaying) {
          if (!isPlaying) {
            _hideControlsDebouncer.cancelDebounceTimer();
          } else if (!_seekController.state.isInteracting) {
            _hideControlsDebouncer.run(() async {
              showControlsNotifier.value = false;
              widget.playbackCallback?.call(
                true,
                FullScreenRequestReason.playbackStateChange,
              );
            });
          }
        });
    _completedStreamSubscription = widget.controller.player.stream.completed
        .listen((isCompleted) {
          if (isCompleted) {
            _seekController.reset(
              position: widget.controller.player.state.position,
              duration: widget.controller.player.state.duration,
            );
          }
        });
  }

  @override
  void dispose() {
    widget.playbackSpeed.removeListener(_onPlaybackSpeedChanged);
    showControlsNotifier.dispose();
    _isPlayingStreamSubscription.cancel();
    _completedStreamSubscription.cancel();
    _hideControlsDebouncer.cancelDebounceTimer();
    _seekController.removeListener(_onSeekInteractionChanged);
    _seekController.dispose();
    super.dispose();
  }

  void _onPlaybackSpeedChanged() {
    widget.controller.player.setRate(widget.playbackSpeed.value);
  }

  void _onSeekInteractionChanged() {
    final isInteracting = _seekController.state.isInteracting;
    if (_isSeekInteractionActive == isInteracting) return;
    _isSeekInteractionActive = isInteracting;
    if (isInteracting) {
      _hideControlsDebouncer.cancelDebounceTimer();
    } else {
      if (widget.controller.player.state.playing) {
        _hideControlsDebouncer.run(() async {
          showControlsNotifier.value = false;
          widget.playbackCallback?.call(
            true,
            FullScreenRequestReason.playbackStateChange,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoWidget = Video(
      controller: widget.controller,
      controls: NoVideoControls,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        widget.transformationController != null
            ? ZoomableVideoViewer(
                transformationController: widget.transformationController!,
                onInteractionLockChanged: widget.onInteractionLockChanged,
                child: videoWidget,
              )
            : videoWidget,
        DoubleTapSeekOverlay(
          enabled: () => !widget.isFromMemories,
          position: () => _seekController.position,
          duration: () => widget.controller.player.state.duration,
          seekBy: _seekController.seekBy,
          onSeekInteraction: () {
            showControlsNotifier.value = true;
          },
          onSingleTap: widget.isFromMemories
              ? null
              : () {
                  showControlsNotifier.value = !showControlsNotifier.value;
                  if (widget.playbackCallback != null) {
                    widget.playbackCallback!(
                      !showControlsNotifier.value,
                      FullScreenRequestReason.userInteraction,
                    );
                  }
                },
          onLongPress: widget.isFromMemories
              ? () {
                  widget.playbackCallback?.call(
                    false,
                    FullScreenRequestReason.userInteraction,
                  );
                  if (widget.controller.player.state.playing) {
                    widget.controller.player.pause();
                  }
                }
              : null,
          onLongPressUp: widget.isFromMemories
              ? () {
                  widget.playbackCallback?.call(
                    true,
                    FullScreenRequestReason.userInteraction,
                  );
                  if (!widget.controller.player.state.playing) {
                    widget.controller.player.play();
                  }
                }
              : null,
        ),
        ValueListenableBuilder(
          valueListenable: showControlsNotifier,
          builder: (context, value, _) {
            return AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: value ? 1 : 0,
              curve: Curves.easeInOutQuad,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!widget.isFromMemories)
                    VideoBottomScrim(
                      hasCaption: widget.file.caption?.isNotEmpty ?? false,
                    ),
                  widget.isFromMemories
                      ? const SizedBox.shrink()
                      : IgnorePointer(
                          ignoring: !value,
                          child: PlayPauseButtonMediaKit(widget.controller),
                        ),
                  widget.isFromMemories
                      ? const SizedBox.shrink()
                      : Positioned(
                          bottom: kVideoProgressRowBottomInset,
                          right: 0,
                          left: 0,
                          child: IgnorePointer(
                            ignoring: !value,
                            child: SafeArea(
                              top: false,
                              left: false,
                              right: false,
                              child: _MediaKitVideoProgressControls(
                                controller: widget.controller,
                                seekController: _seekController,
                              ),
                            ),
                          ),
                        ),
                  widget.isFromMemories
                      ? const SizedBox.shrink()
                      : Positioned(
                          bottom: videoStreamControlBottomInset(
                            widget.file.caption?.isNotEmpty ?? false,
                          ),
                          right: 0,
                          left: 0,
                          child: SafeArea(
                            top: false,
                            left: false,
                            right: false,
                            child: VideoStreamChangeWidget(
                              showControls: value,
                              file: widget.file,
                              isPreviewPlayer: widget.isPreviewPlayer,
                              onStreamChange: () {
                                _seekController.reset(
                                  position:
                                      widget.controller.player.state.position,
                                  duration:
                                      widget.controller.player.state.duration,
                                );
                                widget.onStreamChange();
                              },
                            ),
                          ),
                        ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class PlayPauseButtonMediaKit extends StatefulWidget {
  final VideoController? controller;
  const PlayPauseButtonMediaKit(this.controller, {super.key});

  @override
  State<PlayPauseButtonMediaKit> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButtonMediaKit> {
  bool _isPlaying = true;
  late final StreamSubscription<bool>? isPlayingStreamSubscription;
  late StreamSubscription<bool>? _bufferStateSubscription;
  late var buffering = widget.controller?.player.state.buffering ?? true;

  @override
  void initState() {
    super.initState();

    isPlayingStreamSubscription = widget.controller?.player.stream.playing
        .listen((isPlaying) {
          setState(() {
            _isPlaying = isPlaying;
          });
        });

    _bufferStateSubscription = widget.controller?.player.stream.buffering
        .listen((event) => setState(() => buffering = event));
  }

  @override
  void dispose() {
    isPlayingStreamSubscription?.cancel();
    _bufferStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (buffering) return const EnteLoadingWidget();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (widget.controller?.player.state.playing ?? false) {
          widget.controller?.player.pause();
        } else {
          widget.controller?.player.play();
        }
      },
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(color: strokeFaintDark, width: 1),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          switchInCurve: Curves.easeInOutQuart,
          switchOutCurve: Curves.easeInOutQuart,
          child: _isPlaying
              ? const HugeIcon(
                  icon: HugeIcons.strokeRoundedPause,
                  size: 32,
                  key: ValueKey("pause"),
                  color: Colors.white,
                )
              : const HugeIcon(
                  icon: HugeIcons.strokeRoundedPlay,
                  size: 32,
                  key: ValueKey("play"),
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}

class _MediaKitVideoProgressControls extends StatefulWidget {
  final VideoController controller;
  final VideoSeekController seekController;

  const _MediaKitVideoProgressControls({
    required this.controller,
    required this.seekController,
  });

  @override
  State<_MediaKitVideoProgressControls> createState() =>
      _MediaKitVideoProgressControlsState();
}

class _MediaKitVideoProgressControlsState
    extends State<_MediaKitVideoProgressControls> {
  late final StreamSubscription<Duration> _positionStreamSubscription;
  @override
  void initState() {
    super.initState();
    widget.seekController.addListener(_onSeekStateChanged);
    _positionStreamSubscription = widget.controller.player.stream.position
        .listen((event) {
          widget.seekController.onPlayerPosition(
            event,
            duration: widget.controller.player.state.duration,
          );
        });
  }

  @override
  void dispose() {
    widget.seekController.removeListener(_onSeekStateChanged);
    _positionStreamSubscription.cancel();
    super.dispose();
  }

  void _onSeekStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final canSeek = widget.seekController.canSeek;
    final seekBar = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3.0,
        trackShape: const EqualHeightSliderTrackShape(),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
        padding: EdgeInsets.zero,
        activeTrackColor: backgroundElevatedLight,
        inactiveTrackColor: textBaseDark.withValues(alpha: 0.3),
        thumbColor: backgroundElevatedLight,
        overlayColor: fillMutedDark,
      ),
      child: Slider(
        min: 0.0,
        max: 1.0,
        value: _sliderValue,
        onChangeStart: canSeek
            ? (value) => widget.seekController.beginSliderInteraction()
            : null,
        onChanged: canSeek
            ? (value) =>
                  widget.seekController.updateSliderTarget(_positionAt(value))
            : null,
        divisions: 4500,
        onChangeEnd: canSeek
            ? (value) =>
                  widget.seekController.endSliderInteraction(_positionAt(value))
            : null,
        allowedInteraction: SliderInteraction.tapAndSlide,
      ),
    );
    return VideoProgressRow(
      seekBar: seekBar,
      elapsedTime: secondsToDuration(widget.seekController.position.inSeconds),
      totalTime: secondsToDuration(
        (widget.seekController.duration ?? Duration.zero).inSeconds,
      ),
    );
  }

  Duration _positionAt(double value) {
    final duration = widget.seekController.duration ?? Duration.zero;
    return Duration(milliseconds: (value * duration.inMilliseconds).round());
  }

  double get _sliderValue {
    final duration = widget.seekController.duration;
    if (duration == null || duration <= Duration.zero) return 0;
    return (widget.seekController.position.inMilliseconds /
            duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }
}
