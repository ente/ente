import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:native_video_player/native_video_player.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/seekbar_triggered_event.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/viewer/file/video_control/gallery_video_controls.dart";

class NativeVideoProgressControls extends StatefulWidget {
  final NativeVideoPlayerController controller;
  final int? duration;
  final ValueNotifier<bool> isSeeking;

  const NativeVideoProgressControls(
    this.controller,
    this.duration,
    this.isSeeking, {
    super.key,
  });

  @override
  State<NativeVideoProgressControls> createState() =>
      _NativeVideoProgressControlsState();
}

class _NativeVideoProgressControlsState
    extends State<NativeVideoProgressControls>
    with SingleTickerProviderStateMixin {
  static const _seekReleaseDelay = Duration(milliseconds: 500);
  static const _staleEventWindow = Duration(milliseconds: 1000);
  static const _staleDeltaThreshold = Duration(milliseconds: 1500);

  late final AnimationController _animationController;
  int _elapsedMilliseconds = 0;
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

        _elapsedMilliseconds = 0;
        _animationController.value = event.position.toDouble();
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
            onChangeStart: (value) {
              widget.isSeeking.value = true;
            },
            onChanged: (value) {
              _elapsedMilliseconds = _positionInMilliseconds(value) ?? 0;
              _animationController.value = value;
              _seekTo(value);
            },
            divisions: 4500,
            onChangeEnd: (value) {
              _elapsedMilliseconds = _positionInMilliseconds(value) ?? 0;
              _animationController.value = value;
              _seekTo(value);
              Future.delayed(_seekReleaseDelay, () {
                if (mounted) {
                  widget.isSeeking.value = false;
                }
              });
            },
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

  DateTime? _lastSeekTime;

  void _seekTo(double value) {
    _debouncer.run(() async {
      final position = _positionInMilliseconds(value);
      if (position == null) return;
      _lastSeekTime = DateTime.now();
      await widget.controller.seekTo(Duration(milliseconds: position));
    });
  }

  void _startMovingSeekbar() {
    // Start the seek animation after delayed video playback begins.
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

  void _onPlaybackPositionChanged() async {
    if (widget.isSeeking.value) return;

    final target = widget.controller.playbackPosition.inMilliseconds;
    final duration = widget.controller.videoInfo?.durationInMilliseconds;

    if (widget.controller.playbackStatus == PlaybackStatus.paused ||
        (widget.controller.playbackStatus == PlaybackStatus.stopped &&
            widget.controller.playbackPosition.inSeconds != 0)) {
      if (duration != null && duration > 0) {
        _elapsedMilliseconds = target;
        _animationController.value = (target / duration).clamp(0.0, 1.0);
      }
      return;
    }

    // The position event after zero arrives about 350 ms late.
    if (target == 0) {
      await Future.delayed(const Duration(milliseconds: 450));
    }
    if (!mounted) {
      return;
    }

    if (_lastSeekTime != null &&
        DateTime.now().difference(_lastSeekTime!).inMilliseconds <
            _staleEventWindow.inMilliseconds) {
      if ((target - _elapsedMilliseconds).abs() >
          _staleDeltaThreshold.inMilliseconds) {
        return;
      }
    }

    final previousMilliseconds = _elapsedMilliseconds;
    _elapsedMilliseconds = target;

    final double fractionTarget = duration == null || duration <= 0
        ? 0
        : target / duration;

    final nudge = _durationNudge();

    if ((target - previousMilliseconds).abs() >
        _staleDeltaThreshold.inMilliseconds) {
      _animationController.value = fractionTarget.clamp(0.0, 1.0);
    }

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
