import "dart:async";

import "package:flutter/material.dart";
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
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _isMuted = localSettings.isMemoriesAudioMuted();
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
      initiallyMuted: _isMuted,
      persistMuted: localSettings.setMemoriesAudioMuted,
      player: JustAudioMemoryMusicPlayer(),
      tracks: tracks,
    );
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState != null && lifecycleState != AppLifecycleState.resumed) {
      unawaited(controller.setAppActive(false));
    }
    setState(() => _controller = controller);
  }

  Future<void> _toggleMuted() async {
    final controller = _controller;
    if (controller != null) {
      await controller.toggleMuted();
      return;
    }

    final isMuted = !_isMuted;
    setState(() => _isMuted = isMuted);
    try {
      await localSettings.setMemoriesAudioMuted(isMuted);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to persist memories audio mute state",
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
    return MemoryMusicScope(
      controller: _controller,
      isMuted: _isMuted,
      toggleMuted: _toggleMuted,
      child: widget.child,
    );
  }
}

class MemoryMusicScope extends InheritedNotifier<MemoryMusicController> {
  final bool _isMuted;
  final Future<void> Function() toggleMuted;

  const MemoryMusicScope({
    required MemoryMusicController? controller,
    required bool isMuted,
    required this.toggleMuted,
    required super.child,
    super.key,
  }) : _isMuted = isMuted,
       super(notifier: controller);

  MemoryMusicController? get controller => notifier;

  bool get isMuted => notifier?.isMuted ?? _isMuted;

  static MemoryMusicScope? maybeOf(BuildContext context, {bool listen = true}) {
    return listen
        ? context.dependOnInheritedWidgetOfExactType<MemoryMusicScope>()
        : context.getInheritedWidgetOfExactType<MemoryMusicScope>();
  }

  @override
  bool updateShouldNotify(MemoryMusicScope oldWidget) =>
      _isMuted != oldWidget._isMuted || super.updateShouldNotify(oldWidget);
}
