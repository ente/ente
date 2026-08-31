import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:native_video_player/native_video_player.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/seekbar_triggered_event.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/viewer/file/video_control/gallery_video_controls.dart";
import "package:photos/ui/viewer/file/video_seek_controller.dart";

class NativeVideoProgressControls extends StatefulWidget {
  final NativeVideoPlayerController controller;
  final int? duration;
  final VideoSeekController seekController;

  const NativeVideoProgressControls(
    this.controller,
    this.duration,
    this.seekController, {
    super.key,
  });

  @override
  State<NativeVideoProgressControls> createState() =>
      _NativeVideoProgressControlsState();
}

class _NativeVideoProgressControlsState
    extends State<NativeVideoProgressControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  int _elapsedMilliseconds = 0;
  StreamSubscription<void>? _eventsSubscription;
  StreamSubscription<SeekbarTriggeredEvent>? _seekbarSubscription;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
      value: 0,
    );

    Future.microtask(() {
      _seekbarSubscription = Bus.instance.on<SeekbarTriggeredEvent>().listen((
        event,
      ) {
        if (!mounted || _animationController.value == event.position) return;

        _elapsedMilliseconds = 0;
        _animationController.value = event.position.toDouble();
      });
    });

    _eventsSubscription = widget.controller.events.listen(_listen);
    widget.seekController.addListener(_onSeekStateChanged);

    _startMovingSeekbar();
  }

  @override
  void dispose() {
    _seekbarSubscription?.cancel();
    _eventsSubscription?.cancel();
    widget.seekController.removeListener(_onSeekStateChanged);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (_, _) {
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
            value: _animationController.value,
            onChangeStart: canSeek
                ? (value) => widget.seekController.beginSliderInteraction()
                : null,
            onChanged: canSeek
                ? (value) {
                    final position = _positionInMilliseconds(value);
                    if (position != null) {
                      widget.seekController.updateSliderTarget(
                        Duration(milliseconds: position),
                      );
                    }
                  }
                : null,
            divisions: 4500,
            onChangeEnd: canSeek
                ? (value) {
                    final position = _positionInMilliseconds(value);
                    widget.seekController.endSliderInteraction(
                      position == null
                          ? widget.seekController.position
                          : Duration(milliseconds: position),
                    );
                  }
                : null,
            allowedInteraction: SliderInteraction.tapAndSlide,
          ),
        );
        return VideoProgressRow(
          seekBar: seekBar,
          elapsedTime: secondsToDuration(_elapsedMilliseconds ~/ 1000),
          totalTime: secondsToDuration(
            (_effectiveDurationInMilliseconds() ?? 0) ~/ 1000,
          ),
        );
      },
    );
  }

  void _startMovingSeekbar() {
    // Start the seek animation after delayed video playback begins.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted ||
          widget.seekController.state.phase != VideoSeekPhase.idle ||
          widget.controller.playbackStatus != PlaybackStatus.playing) {
        return;
      }
      final nudge = _durationNudge();
      unawaited(
        _animationController.animateTo(
          nudge,
          duration: const Duration(seconds: 1),
        ),
      );
    });
  }

  void _listen(PlaybackEvent playerData) {
    switch (playerData) {
      case PlaybackStatusChangedEvent():
        _onPlaybackStatusChanged();
        break;
      case PlaybackPositionChangedEvent():
        _onPlaybackPositionChanged();
        break;
      case PlaybackEndedEvent():
        _elapsedMilliseconds = 0;
        _animationController.value = 0;
      default:
    }
  }

  void _onPlaybackStatusChanged() {
    if (widget.controller.playbackStatus == PlaybackStatus.paused) {
      _animationController.stop();
    }
  }

  void _onPlaybackPositionChanged() {
    final target = widget.controller.playbackPosition.inMilliseconds;
    if (widget.controller.playbackStatus == PlaybackStatus.stopped &&
        target != 0) {
      return;
    }
    final duration = _effectiveDurationInMilliseconds();
    widget.seekController.onPlayerPosition(
      Duration(milliseconds: target),
      duration: duration == null ? null : Duration(milliseconds: duration),
    );
  }

  void _onSeekStateChanged() => _syncFromController();

  void _syncFromController() {
    if (!mounted) return;
    final duration = _effectiveDurationInMilliseconds();
    final elapsed = widget.seekController.position.inMilliseconds;
    if (_elapsedMilliseconds != elapsed) {
      setState(() {
        _elapsedMilliseconds = elapsed;
      });
    }
    if (duration != null && duration > 0) {
      final fraction = (elapsed / duration).clamp(0.0, 1.0);
      if (widget.seekController.state.phase == VideoSeekPhase.idle &&
          widget.controller.playbackStatus == PlaybackStatus.playing) {
        unawaited(
          _animationController.animateTo(
            (fraction + _durationNudge()).clamp(0.0, 1.0),
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        _animationController.stop();
        _animationController.value = fraction;
      }
    }
  }

  int? _effectiveDurationInMilliseconds() {
    final controllerDurationInMilliseconds =
        widget.controller.videoInfo?.durationInMilliseconds;
    if (controllerDurationInMilliseconds != null &&
        controllerDurationInMilliseconds > 0) {
      return controllerDurationInMilliseconds;
    }
    if (widget.duration != null && widget.duration! > 0) {
      return widget.duration! * 1000;
    }
    return null;
  }

  int? _positionInMilliseconds(double value) {
    final duration = _effectiveDurationInMilliseconds();
    return duration == null ? null : (value * duration).round();
  }

  double _durationNudge() {
    final durationInMilliseconds = _effectiveDurationInMilliseconds();
    if (durationInMilliseconds == null) {
      return 0;
    }
    final durationInSeconds = durationInMilliseconds / 1000;
    if (durationInSeconds <= 0) {
      return 0;
    }
    return (1 / durationInSeconds).clamp(0.0, 1.0);
  }
}
