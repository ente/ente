import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:native_video_player/native_video_player.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/seekbar_triggered_event.dart";
import "package:photos/theme/colors.dart";

class SeekBar extends StatefulWidget {
  final NativeVideoPlayerController controller;
  final int? duration;
  final ValueNotifier<bool> isSeeking;
  const SeekBar(this.controller, this.duration, this.isSeeking, {super.key});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  final _debouncer = Debouncer(
    const Duration(milliseconds: 100),
    executionInterval: const Duration(milliseconds: 325),
  );
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

        _animationController.value = event.position.toDouble();
        setState(() {});
      });
    });

    _eventsSubscription = widget.controller.events.listen(_listen);

    _startMovingSeekbar();
  }

  @override
  void dispose() {
    _seekbarSubscription?.cancel();
    _eventsSubscription?.cancel();
    _animationController.dispose();
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (_, _) {
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 1.0,
            tickMarkShape: SliderTickMarkShape.noTickMark,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
            activeTrackColor: backgroundElevatedLight,
            inactiveTrackColor: fillMutedDark,
            thumbColor: backgroundElevatedLight,
            overlayColor: fillMutedDark,
          ),
          child: Slider(
            min: 0.0,
            max: 1.0,
            value: _animationController.value,
            onChangeStart: (value) {
              widget.isSeeking.value = true;
            },
            onChanged: (value) {
              setState(() {
                _animationController.value = value;
              });
              _seekTo(value);
            },
            divisions: 4500,
            onChangeEnd: (value) {
              setState(() {
                _animationController.value = value;
              });
              _seekTo(value);
              widget.isSeeking.value = false;
            },
            allowedInteraction: SliderInteraction.tapAndSlide,
          ),
        );
      },
    );
  }

  void _seekTo(double value) {
    _debouncer.run(() async {
      final durationInMilliseconds = _effectiveDurationInMilliseconds();
      if (durationInMilliseconds == null) {
        return;
      }
      unawaited(
        widget.controller.seekTo(
          Duration(milliseconds: (value * durationInMilliseconds).round()),
        ),
      );
    });
  }

  void _startMovingSeekbar() {
    //Video starts playing after a slight delay. This delay is to ensure that
    //the seek bar animation starts after the video starts playing.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) {
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
        // Emitted when playback status changes (playing, paused, or stopped)
        _onPlaybackStatusChanged();
        break;
      case PlaybackPositionChangedEvent():
        // Emitted when playback position changes
        _onPlaybackPositionChanged();
        break;
      case PlaybackEndedEvent():
        _animationController.value = 0;
      default:
    }
  }

  void _onPlaybackStatusChanged() {
    if (widget.controller.playbackStatus == PlaybackStatus.paused) {
      _animationController.stop();
    }
  }

  void _onPlaybackPositionChanged() async {
    if (widget.controller.playbackStatus == PlaybackStatus.paused ||
        (widget.controller.playbackStatus == PlaybackStatus.stopped &&
            widget.controller.playbackPosition.inSeconds != 0)) {
      return;
    }
    final target = widget.controller.playbackPosition.inMilliseconds;

    //There is a slight delay (around 350 ms) for the event being listened to
    //by this listener on the next target (target that comes after 0). Adding
    //this buffer to keep the seek bar animation smooth.
    if (target == 0) {
      await Future.delayed(const Duration(milliseconds: 450));
    }
    if (!mounted) {
      return;
    }

    final duration = widget.controller.videoInfo?.durationInMilliseconds;
    final double fractionTarget = duration == null || duration <= 0
        ? 0
        : target / duration;

    final nudge = _durationNudge();
    unawaited(
      _animationController.animateTo(
        (fractionTarget + nudge).clamp(0.0, 1.0),
        duration: const Duration(seconds: 1),
      ),
    );
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
