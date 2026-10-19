import "dart:async";

import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/video_mute_changed_event.dart";
import "package:photos/service_locator.dart";

class VideoMuteButton extends StatefulWidget {
  const VideoMuteButton({super.key});

  @override
  State<VideoMuteButton> createState() => _VideoMuteButtonState();
}

class _VideoMuteButtonState extends State<VideoMuteButton> {
  late bool _isMuted;
  StreamSubscription<VideoMuteChangedEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _isMuted = localSettings.isMuted();
    _subscription = Bus.instance.on<VideoMuteChangedEvent>().listen((event) {
      if (mounted) {
        setState(() {
          _isMuted = event.isMuted;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VideoMuteIconButton(
      isMuted: _isMuted,
      onPressed: () async {
        final newValue = !_isMuted;
        await localSettings.setIsMuted(newValue);
        Bus.instance.fire(VideoMuteChangedEvent(newValue));
      },
    );
  }
}

class VideoMuteIconButton extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onPressed;

  const VideoMuteIconButton({
    required this.isMuted,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        style: IconButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: Colors.transparent,
        ),
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          switchInCurve: Curves.easeInOutQuart,
          switchOutCurve: Curves.easeInOutQuart,
          child: HugeIcon(
            key: ValueKey(isMuted),
            icon: isMuted
                ? HugeIcons.strokeRoundedVolumeOff
                : HugeIcons.strokeRoundedVolumeHigh,
            color: Colors.white,
            size: 20,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
