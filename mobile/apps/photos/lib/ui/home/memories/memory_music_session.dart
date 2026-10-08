import "dart:async";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memories/just_audio_memory_music_player.dart";
import "package:photos/services/memories/memory_music_controller.dart";
import "package:photos/services/memories/memory_music_selector.dart";
import "package:photos/services/memories/memory_music_service.dart";

class MemoryMusicSession extends StatefulWidget {
  final List<String> memoryIDs;
  final Widget child;

  const MemoryMusicSession({
    required this.memoryIDs,
    required this.child,
    super.key,
  });

  @override
  State<MemoryMusicSession> createState() => _MemoryMusicSessionState();
}

class _MemoryMusicSessionState extends State<MemoryMusicSession>
    with WidgetsBindingObserver {
  static final _logger = Logger("MemoryMusicSession");

  MemoryMusicController? _controller;
  late bool _isMusicMuted;
  late bool _isVideoMuted;

  @override
  void initState() {
    super.initState();
    _isMusicMuted = localSettings.isMemoriesMusicMuted();
    _isVideoMuted = localSettings.isMemoriesVideoMuted();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final tracks = await MemoryMusicService.instance.prepare();
    if (!mounted || tracks.isEmpty) return;
    final assignments = assignMemoryMusicTracks(
      memoryIDs: widget.memoryIDs,
      tracks: tracks,
    );
    final controller = MemoryMusicController(
      assignments: assignments,
      initiallyMuted: _isMusicMuted,
      persistMuted: localSettings.setMemoriesMusicMuted,
      player: JustAudioMemoryMusicPlayer(),
      tracks: tracks,
    );
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      unawaited(controller.setAppActive(false));
    }
    setState(() => _controller = controller);
  }

  Future<void> _toggleMusicMuted() async {
    final controller = _controller;
    if (controller != null) {
      await controller.toggleMuted();
      return;
    }

    final isMuted = !_isMusicMuted;
    setState(() => _isMusicMuted = isMuted);
    try {
      await localSettings.setMemoriesMusicMuted(isMuted);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to persist memories music mute state",
        error,
        stackTrace,
      );
    }
  }

  Future<void> _toggleVideoMuted() async {
    final isMuted = !_isVideoMuted;
    setState(() => _isVideoMuted = isMuted);
    try {
      await localSettings.setMemoriesVideoMuted(isMuted);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to persist memories video mute state",
        error,
        stackTrace,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.setAppActive(state == AppLifecycleState.resumed));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MemoryAudioScope(
      controller: _controller,
      isMusicMuted: _isMusicMuted,
      isVideoMuted: _isVideoMuted,
      toggleMusicMuted: _toggleMusicMuted,
      toggleVideoMuted: _toggleVideoMuted,
      child: widget.child,
    );
  }
}

class MemoryAudioScope extends InheritedNotifier<MemoryMusicController> {
  final bool _isMusicMuted;
  final bool isVideoMuted;
  final Future<void> Function() toggleMusicMuted;
  final Future<void> Function() toggleVideoMuted;

  const MemoryAudioScope({
    required MemoryMusicController? controller,
    required bool isMusicMuted,
    required this.isVideoMuted,
    required this.toggleMusicMuted,
    required this.toggleVideoMuted,
    required super.child,
    super.key,
  }) : _isMusicMuted = isMusicMuted,
       super(notifier: controller);

  MemoryMusicController? get controller => notifier;

  bool get isMusicMuted => notifier?.isMuted ?? _isMusicMuted;

  void activateMusic(
    String memoryID, {
    required bool currentItemIsVideo,
    bool viewerActionPaused = false,
  }) {
    final controller = this.controller;
    if (controller == null) return;
    unawaited(controller.setViewerActionPaused(viewerActionPaused));
    unawaited(
      controller.activateMemory(
        memoryID,
        currentItemIsVideo: currentItemIsVideo,
      ),
    );
  }

  void setMusicViewerActionPaused(bool paused) {
    unawaited(controller?.setViewerActionPaused(paused));
  }

  static MemoryAudioScope? maybeOf(BuildContext context, {bool listen = true}) {
    return listen
        ? context.dependOnInheritedWidgetOfExactType<MemoryAudioScope>()
        : context.getInheritedWidgetOfExactType<MemoryAudioScope>();
  }

  @override
  bool updateShouldNotify(MemoryAudioScope oldWidget) =>
      _isMusicMuted != oldWidget._isMusicMuted ||
      isVideoMuted != oldWidget.isVideoMuted ||
      super.updateShouldNotify(oldWidget);
}

class MemoryAudioMuteButton extends StatelessWidget {
  final MemoryAudioScope memoryAudio;
  final bool mutesVideoAudio;

  const MemoryAudioMuteButton(
    this.memoryAudio, {
    this.mutesVideoAudio = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isMuted = mutesVideoAudio
        ? memoryAudio.isVideoMuted
        : memoryAudio.isMusicMuted;
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: isMuted
            ? context.strings.unmuteAudio
            : context.strings.muteAudio,
        padding: const EdgeInsets.all(7),
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
          minimumSize: const Size.square(48),
          maximumSize: const Size.square(48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: Colors.transparent,
        ),
        onPressed: () => unawaited(
          mutesVideoAudio
              ? memoryAudio.toggleVideoMuted()
              : memoryAudio.toggleMusicMuted(),
        ),
        icon: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0x66000000),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 34,
            child: Center(
              child: HugeIcon(
                icon: isMuted
                    ? HugeIcons.strokeRoundedVolumeOff
                    : HugeIcons.strokeRoundedVolumeHigh,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
