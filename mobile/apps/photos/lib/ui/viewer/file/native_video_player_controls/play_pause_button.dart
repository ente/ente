import "dart:async";

import "package:flutter/material.dart";
import "package:native_video_player/native_video_player.dart";
import "package:photos/theme/colors.dart";

class PlayPauseButton extends StatefulWidget {
  final NativeVideoPlayerController? controller;
  const PlayPauseButton(this.controller, {super.key});

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton> {
  bool _isPlaying = true;

  StreamSubscription<PlaybackEvent>? subscription;

  @override
  void initState() {
    super.initState();
    subscription = widget.controller?.events.listen(listen);
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  void listen(PlaybackEvent event) {
    switch (event) {
      case PlaybackStatusChangedEvent():
        _onPlaybackStatusChanged();
        break;
      default:
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_playbackStatus == PlaybackStatus.playing) {
          widget.controller?.pause();
        } else {
          widget.controller?.play();
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
              ? const Icon(
                  Icons.pause,
                  size: 32,
                  key: ValueKey("pause"),
                  color: Colors.white,
                )
              : const Icon(
                  Icons.play_arrow,
                  size: 36,
                  key: ValueKey("play"),
                  color: Colors.white,
                ),
        ),
      ),
    );
  }

  PlaybackStatus? get _playbackStatus => widget.controller?.playbackStatus;

  void _onPlaybackStatusChanged() {
    if (_playbackStatus == PlaybackStatus.playing) {
      setState(() {
        _isPlaying = true;
      });
    } else {
      setState(() {
        _isPlaying = false;
      });
    }
  }
}
