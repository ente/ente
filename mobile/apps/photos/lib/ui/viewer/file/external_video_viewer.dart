import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:native_video_player/native_video_player.dart";
import "package:photos/ui/viewer/file/native_video_player_controls/play_pause_button.dart";
import "package:photos/ui/viewer/file/native_video_player_controls/seek_bar.dart";
import "package:photos/ui/viewer/file/video_control/gallery_video_controls.dart";
import "package:photos/ui/viewer/file/video_control/mute_button.dart";
import "package:photos/ui/viewer/file/video_control/video_speed_bottom_sheet.dart";
import "package:photos/ui/viewer/file/video_double_tap_seek.dart";
import "package:photos/ui/viewer/file/video_seek_controller.dart";
import "package:photos/ui/viewer/file/viewer_app_bar.dart";
import "package:video_player/video_player.dart" as vp;
import "package:wakelock_plus/wakelock_plus.dart";

class ExternalVideoViewer extends StatefulWidget {
  final String uri;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onBackPressed;

  const ExternalVideoViewer({
    required this.uri,
    required this.onFullscreenChanged,
    required this.onBackPressed,
    super.key,
  });

  @override
  ExternalVideoViewerState createState() => ExternalVideoViewerState();
}

class ExternalVideoViewerState extends State<ExternalVideoViewer>
    with WidgetsBindingObserver {
  final _logger = Logger("ExternalVideoViewer");
  NativeVideoPlayerController? _controller;
  StreamSubscription<PlaybackEvent>? _subscription;
  late final VideoSeekController _seekController;
  Timer? _hideControlsTimer;
  OverlayEntry? _longPressSpeedIndicator;
  bool _hasError = false;
  bool _isPlaybackReady = false;
  bool _preparingPlayback = false;
  bool _isFullscreen = false;
  bool _isForeground = true;
  bool _resumePlayback = false;
  bool _showControls = true;
  bool _isSeeking = false;
  bool _isShowingMenu = false;
  double _playbackSpeed = 1;
  double? _displayAspectRatio;

  NativeVideoPlayerController? get controller => _controller;
  bool get isFullscreen => _isFullscreen;

  Duration? get _duration {
    final milliseconds = _controller?.videoInfo?.durationInMilliseconds;
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _isForeground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _seekController = VideoSeekController(
      seek: (position) async => _controller?.seekTo(position),
      readPosition: () => _controller?.playbackPosition ?? Duration.zero,
      readDuration: () => _duration,
      onSeekError: (error, stackTrace) {
        _logger.warning("Could not seek external video", error, stackTrace);
      },
    )..addListener(_onSeekChanged);
  }

  Future<void> _initializeController(
    NativeVideoPlayerController controller,
  ) async {
    if (!mounted) {
      controller.dispose();
      return;
    }
    _controller = controller;
    _subscription = controller.events.listen(_onPlaybackEvent);
    await _run(() async {
      final uri = Uri.tryParse(widget.uri);
      final path = uri?.scheme == "file" ? uri!.toFilePath() : widget.uri;
      if (Platform.isIOS) await _probeIosAspectRatio(path);
      if (!mounted || _hasError) return;
      await controller.loadVideo(
        VideoSource(path: path, type: VideoSourceType.file),
      );
    });
  }

  Future<void> _probeIosAspectRatio(String path) async {
    // Native videoInfo omits rotation. A platform view probe also avoids
    // texture composition failures when reading rotated iOS videos.
    final metadataController = vp.VideoPlayerController.file(
      File(path),
      viewType: vp.VideoViewType.platformView,
    );
    try {
      await metadataController.initialize().timeout(const Duration(seconds: 4));
      final aspectRatio = metadataController.value.aspectRatio;
      if (mounted && aspectRatio > 0) _displayAspectRatio = aspectRatio;
    } catch (error, stackTrace) {
      _logger.warning(
        "Could not read external video dimensions",
        error,
        stackTrace,
      );
    } finally {
      try {
        await metadataController.dispose().timeout(const Duration(seconds: 4));
      } catch (error, stackTrace) {
        _logger.warning(
          "Could not dispose video metadata probe",
          error,
          stackTrace,
        );
      }
    }
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    if (!mounted) return;
    switch (event) {
      case PlaybackReadyEvent():
        unawaited(_onPlaybackReady());
      case PlaybackEndedEvent():
        unawaited(_loopVideo());
      case PlaybackErrorEvent():
        _onPlaybackError(event.errorMessage);
      case PlaybackPositionChangedEvent():
        _seekController.onPlayerPosition(
          _controller!.playbackPosition,
          duration: _duration,
        );
      case PlaybackStatusChangedEvent():
        if (event.status != PlaybackStatus.playing) {
          setState(() => _showControls = true);
        }
        unawaited(
          WakelockPlus.toggle(
            enable: _isForeground && event.status == PlaybackStatus.playing,
          ),
        );
        _scheduleHideControls();
      case VolumeChangedEvent():
        setState(() {});
      default:
    }
  }

  Future<void> _onPlaybackReady() async {
    if (_isPlaybackReady || _preparingPlayback) return;
    _preparingPlayback = true;
    await _run(() async {
      final controller = _controller!;
      await controller.setVolume(controller.volume);
      if (!mounted || _hasError) return;
      _seekController.updateDuration(_duration);
      setState(() => _isPlaybackReady = true);
      if (_isForeground) {
        await controller.play();
      } else {
        _resumePlayback = true;
      }
    });
  }

  Future<void> _loopVideo() async {
    if (!_isForeground ||
        _controller?.playbackStatus != PlaybackStatus.playing) {
      return;
    }
    await _run(() async {
      final controller = _controller!;
      _seekController.reset(duration: _duration);
      await controller.seekTo(Duration.zero);
      if (mounted &&
          _isForeground &&
          controller.playbackStatus == PlaybackStatus.playing) {
        await controller.play();
      }
    });
  }

  Future<void> _run(Future<void> Function() command) async {
    if (!mounted || _hasError) return;
    try {
      await command();
    } catch (error, stackTrace) {
      if (mounted) _onPlaybackError(error, stackTrace);
    }
  }

  void _onPlaybackError(Object error, [StackTrace? stackTrace]) {
    _logger.warning("Could not play external video", error, stackTrace);
    if (!mounted || _hasError) return;
    _hideControlsTimer?.cancel();
    _removeLongPressSpeedIndicator();
    unawaited(_subscription?.cancel());
    _controller?.dispose();
    _controller = null;
    unawaited(WakelockPlus.disable());
    if (_isFullscreen) unawaited(exitFullscreen());
    setState(() => _hasError = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_isForeground) return;
      _resumePlayback =
          !_isPlaybackReady ||
          _controller?.playbackStatus == PlaybackStatus.playing;
      _isForeground = false;
      _stopLongPressSpeed();
      unawaited(_run(() async => _controller?.pause()));
      unawaited(WakelockPlus.disable());
    } else if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      if (_resumePlayback && _isPlaybackReady) {
        _resumePlayback = false;
        unawaited(_run(() async => _controller?.play()));
      }
    }
  }

  void _onSeekChanged() {
    if (!mounted) return;
    final isSeeking = _seekController.state.isInteracting;
    if (_isSeeking != isSeeking) {
      setState(() {
        _isSeeking = isSeeking;
        if (isSeeking) _showControls = true;
      });
      _scheduleHideControls();
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_isForeground &&
        _controller?.playbackStatus == PlaybackStatus.playing &&
        !_isSeeking &&
        !_isShowingMenu &&
        _longPressSpeedIndicator == null) {
      _hideControlsTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (!mounted || _isFullscreen == fullscreen) return;
    setState(() => _isFullscreen = fullscreen);
    widget.onFullscreenChanged(fullscreen);
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    await SystemChrome.setPreferredOrientations(
      fullscreen
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  Future<void> exitFullscreen() => _setFullscreen(false);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _removeLongPressSpeedIndicator();
    unawaited(_subscription?.cancel());
    _controller?.dispose();
    _seekController.dispose();
    unawaited(WakelockPlus.disable());
    if (_isFullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
    super.dispose();
  }

  void _startLongPressSpeed() {
    if (!_isForeground ||
        _controller?.playbackStatus != PlaybackStatus.playing ||
        _longPressSpeedIndicator != null) {
      return;
    }
    _longPressSpeedIndicator = showVideoLongPressSpeedIndicator(context);
    _hideControlsTimer?.cancel();
    unawaited(
      _run(() => _controller!.setPlaybackSpeed(kVideoLongPressPlaybackSpeed)),
    );
  }

  void _stopLongPressSpeed() {
    if (_longPressSpeedIndicator == null) return;
    _removeLongPressSpeedIndicator();
    unawaited(_run(() async => _controller?.setPlaybackSpeed(_playbackSpeed)));
    _scheduleHideControls();
  }

  void _removeLongPressSpeedIndicator() {
    _longPressSpeedIndicator?.remove();
    _longPressSpeedIndicator?.dispose();
    _longPressSpeedIndicator = null;
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _scheduleHideControls();
  }

  void _onBackPressed() {
    if (_isFullscreen) {
      unawaited(exitFullscreen());
    } else {
      widget.onBackPressed();
    }
  }

  Future<void> _showPlaybackMenu(BuildContext buttonContext) async {
    _isShowingMenu = true;
    _hideControlsTimer?.cancel();
    try {
      final selected = await showEntePopupMenu<bool>(
        context: buttonContext,
        options: [
          EntePopupMenuOption(
            value: true,
            label: context.strings.playbackSpeed,
            leadingWidget: const HugeIcon(
              icon: HugeIcons.strokeRoundedDashboardSpeed02,
              size: IconSizes.small,
            ),
            trailingWidget: Text(
              _playbackSpeed == 1 ? "1x" : "${_playbackSpeed}x",
              style: TextStyles.tiny,
            ),
          ),
        ],
      );
      if (!mounted || _hasError || selected != true) return;
      await showVideoSpeedBottomSheet(
        context,
        currentSpeed: _playbackSpeed,
        onSpeedSelected: (speed) {
          setState(() => _playbackSpeed = speed);
          unawaited(_run(() => _controller!.setPlaybackSpeed(speed)));
        },
      );
    } finally {
      _isShowingMenu = false;
      if (mounted) _scheduleHideControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _controller?.videoInfo;
    final aspectRatio =
        _displayAspectRatio ??
        (info != null && info.width > 0 && info.height > 0
            ? info.width / info.height
            : 16 / 9);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_hasError)
            const Center(child: Icon(Icons.error_outline, color: Colors.white))
          else ...[
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: NativeVideoPlayerView(
                  onViewReady: _initializeController,
                ),
              ),
            ),
            if (!_isPlaybackReady)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_isPlaybackReady) ..._buildControls(),
          ],
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top + 80,
            child: ViewerAppBar(
              visible: _hasError || _showControls,
              onBackPressed: _onBackPressed,
              actions: _isPlaybackReady && !_hasError
                  ? [
                      IconButton(
                        onPressed: () =>
                            unawaited(_setFullscreen(!_isFullscreen)),
                        icon: Icon(
                          _isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                        ),
                      ),
                      Builder(
                        builder: (buttonContext) => IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).moreButtonTooltip,
                          onPressed: () =>
                              unawaited(_showPlaybackMenu(buttonContext)),
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedMoreVertical,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ]
                  : [],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildControls() {
    final controller = _controller!;
    final isMuted = controller.volume == 0;
    return [
      AnimatedOpacity(
        opacity: _showControls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: const VideoBottomScrim(hasCaption: false),
      ),
      Listener(
        // Long-press cancellation only fires before recognition in Flutter.
        onPointerCancel: (_) => _stopLongPressSpeed(),
        child: DoubleTapSeekOverlay(
          enabled: () => _isPlaybackReady && !_hasError,
          position: () => _seekController.position,
          duration: () => _seekController.duration ?? Duration.zero,
          seekBy: _seekController.seekBy,
          onSingleTap: _toggleControls,
          onSeekInteraction: () {
            setState(() => _showControls = true);
            _scheduleHideControls();
          },
          onLongPress: _startLongPressSpeed,
          onLongPressUp: _stopLongPressSpeed,
          onLongPressCancel: _stopLongPressSpeed,
        ),
      ),
      IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInQuad,
          child: Center(child: PlayPauseButton(controller)),
        ),
      ),
      GalleryBottomControlsPositioned(
        bottom: kVideoProgressRowBottomInset,
        child: SafeArea(
          top: false,
          child: IgnorePointer(
            ignoring: !_showControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInQuad,
              child: NativeVideoProgressControls(
                controller,
                _duration?.inSeconds,
                _seekController,
                muteButton: VideoMuteIconButton(
                  isMuted: isMuted,
                  onPressed: () => unawaited(
                    _run(() => controller.setVolume(isMuted ? 1 : 0)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
