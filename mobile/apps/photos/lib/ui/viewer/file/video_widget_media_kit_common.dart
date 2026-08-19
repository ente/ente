import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:media_kit_video/media_kit_video.dart";
import "package:photos/models/file/file.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/viewer/file/video_control/gallery_video_controls.dart";
import "package:photos/ui/viewer/file/video_control/video_speed_bottom_sheet.dart";
import "package:photos/ui/viewer/file/video_control/video_speed_button.dart";
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
  });

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  final showControlsNotifier = ValueNotifier<bool>(true);
  final _hideControlsDebouncer = Debouncer(const Duration(milliseconds: 2000));
  final _isSeekingNotifier = ValueNotifier<bool>(false);
  late final StreamSubscription<bool> _isPlayingStreamSubscription;
  final _playbackSpeed = ValueNotifier<double>(1.0);

  @override
  void initState() {
    super.initState();
    widget.controller.player.setRate(_playbackSpeed.value);
    _isPlayingStreamSubscription = widget.controller.player.stream.playing
        .listen((isPlaying) {
          if (isPlaying && !_isSeekingNotifier.value) {
            _hideControlsDebouncer.run(() async {
              showControlsNotifier.value = false;
              widget.playbackCallback?.call(
                true,
                FullScreenRequestReason.playbackStateChange,
              );
            });
          }
        });

    _isSeekingNotifier.addListener(isSeekingListener);
  }

  @override
  void dispose() {
    showControlsNotifier.dispose();
    _isPlayingStreamSubscription.cancel();
    _hideControlsDebouncer.cancelDebounceTimer();
    _isSeekingNotifier.removeListener(isSeekingListener);
    _isSeekingNotifier.dispose();
    _playbackSpeed.dispose();
    super.dispose();
  }

  void isSeekingListener() {
    if (_isSeekingNotifier.value) {
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
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.isFromMemories
                        ? null
                        : () {
                            showControlsNotifier.value =
                                !showControlsNotifier.value;
                            if (widget.playbackCallback != null) {
                              widget.playbackCallback!(
                                !showControlsNotifier.value,
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
                        if (widget.controller.player.state.playing) {
                          widget.controller.player.pause();
                        }
                      }
                    },
                    onLongPressUp: () {
                      if (widget.isFromMemories) {
                        widget.playbackCallback?.call(
                          true,
                          FullScreenRequestReason.userInteraction,
                        );
                        if (!widget.controller.player.state.playing) {
                          widget.controller.player.play();
                        }
                      }
                    },
                    child: Container(
                      constraints: const BoxConstraints.expand(),
                    ),
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
                                isSeekingNotifier: _isSeekingNotifier,
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
                            child: Stack(
                              children: [
                                ValueListenableBuilder<double>(
                                  valueListenable: _playbackSpeed,
                                  builder: (context, speed, _) {
                                    return VideoSpeedButton(
                                      showControls: value,
                                      playbackSpeed: speed,
                                      onTap: () {
                                        showVideoSpeedBottomSheet(
                                          context,
                                          currentSpeed: speed,
                                          onSpeedSelected: (newSpeed) {
                                            _playbackSpeed.value = newSpeed;
                                            widget.controller.player.setRate(
                                              newSpeed,
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                                VideoStreamChangeWidget(
                                  showControls: value,
                                  file: widget.file,
                                  isPreviewPlayer: widget.isPreviewPlayer,
                                  onStreamChange: widget.onStreamChange,
                                ),
                              ],
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
  final ValueNotifier<bool> isSeekingNotifier;

  const _MediaKitVideoProgressControls({
    required this.controller,
    required this.isSeekingNotifier,
  });

  @override
  State<_MediaKitVideoProgressControls> createState() =>
      _MediaKitVideoProgressControlsState();
}

class _MediaKitVideoProgressControlsState
    extends State<_MediaKitVideoProgressControls> {
  double _sliderValue = 0.0;
  Duration _elapsedTime = Duration.zero;
  late final StreamSubscription<Duration> _positionStreamSubscription;
  final _debouncer = Debouncer(
    const Duration(milliseconds: 300),
    executionInterval: const Duration(milliseconds: 300),
  );
  @override
  void initState() {
    super.initState();
    _positionStreamSubscription = widget.controller.player.stream.position
        .listen((event) {
          if (widget.isSeekingNotifier.value) return;
          if (mounted) {
            setState(() {
              _elapsedTime = event;
              _sliderValue =
                  (event.inMilliseconds /
                          widget
                              .controller
                              .player
                              .state
                              .duration
                              .inMilliseconds)
                      .clamp(0, 1);
              if (_sliderValue.isNaN) {
                _sliderValue = 0.0;
              }
            });
          }
        });
  }

  @override
  void dispose() {
    _positionStreamSubscription.cancel();
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        onChangeStart: (value) {
          if (mounted) {
            setState(() {
              widget.isSeekingNotifier.value = true;
            });
          }
        },
        onChanged: (value) {
          if (mounted) {
            setState(() {
              _sliderValue = value;
              _elapsedTime = _positionAt(value);
            });
          }

          _debouncer.run(() async {
            await widget.controller.player.seek(_positionAt(value));
          });
        },
        divisions: 4500,
        onChangeEnd: (value) async {
          await widget.controller.player.seek(_positionAt(value));
          if (mounted) {
            setState(() {
              widget.isSeekingNotifier.value = false;
            });
          }
        },
        allowedInteraction: SliderInteraction.tapAndSlide,
      ),
    );
    return VideoProgressRow(
      seekBar: seekBar,
      elapsedTime: secondsToDuration(_elapsedTime.inSeconds),
      totalTime: secondsToDuration(
        widget.controller.player.state.duration.inSeconds,
      ),
    );
  }

  Duration _positionAt(double value) {
    return Duration(
      milliseconds:
          (value * widget.controller.player.state.duration.inMilliseconds)
              .round(),
    );
  }
}
