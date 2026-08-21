import "dart:async";

import "package:ente_components/components/buttons/icon_button_component.dart";
import "package:ente_components/theme/icon_sizes.dart";
import "package:ente_components/theme/spacing.dart";
import "package:ente_components/theme/text_styles.dart";
import "package:ente_components/theme/theme.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/viewer/file/file_widget.dart";

class AlbumSlideshowPage extends StatefulWidget {
  AlbumSlideshowPage({
    required this.files,
    required this.albumName,
    super.key,
  }) {
    if (files.isEmpty) {
      throw ArgumentError("files must not be empty");
    }
  }

  final List<EnteFile> files;
  final String albumName;

  @override
  State<AlbumSlideshowPage> createState() => _AlbumSlideshowPageState();
}

class _SlideSlot {
  _SlideSlot(this._index);

  int? _index;
  bool isReady = false;

  int? get index => _index;

  set index(int? value) {
    if (_index == value) return;

    _index = value;
    isReady = false;
  }
}

class _AlbumSlideshowPageState extends State<AlbumSlideshowPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Duration _slideDuration = Duration(seconds: 5);
  static const Duration _mediaReadyTimeout = Duration(seconds: 10);
  static const Duration _crossFadeDuration = Duration(milliseconds: 600);
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  static final ThemeData _controlsTheme = ComponentTheme.darkTheme();

  Timer? _advanceTimer;
  Timer? _controlsHideTimer;
  late final AnimationController _crossFadeController;
  late final CurvedAnimation _crossFadeAnimation;
  late final List<_SlideSlot> _slots;
  int _currentSlotIndex = 0;
  bool _controlsVisible = true;
  bool _isPlaying = true;
  bool _accessibleNavigation = false;
  bool _wakeLockRequested = false;
  bool _isForeground = false;

  List<EnteFile> get _files => widget.files;
  int get _nextSlotIndex => 1 - _currentSlotIndex;
  int? get _nextIndex => _slots[_nextSlotIndex].index;

  int? _indexAfter(int index) {
    if (_files.length < 2) return null;
    return (index + 1) % _files.length;
  }

  bool get _isTransitioning =>
      _crossFadeController.status != AnimationStatus.dismissed;
  bool get _isCurrentSlideReady => _slots[_currentSlotIndex].isReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slots = [_SlideSlot(0), _SlideSlot(_indexAfter(0))];
    _crossFadeController = AnimationController(
      vsync: this,
      duration: _crossFadeDuration,
    )..addStatusListener(_onCrossFadeStatusChanged);
    _crossFadeAnimation = CurvedAnimation(
      parent: _crossFadeController,
      curve: Curves.easeInOut,
    );
    _isForeground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
        AppLifecycleState.resumed;
    _setAlbumSlideshowWakeLock(_isForeground && _isPlaying);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSystemUi();
      _scheduleControlsHide();
      _scheduleAdvance();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    if (_accessibleNavigation == accessibleNavigation) return;

    _accessibleNavigation = accessibleNavigation;
    if (_accessibleNavigation) {
      _controlsHideTimer?.cancel();
    } else {
      _scheduleControlsHide();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      _setAlbumSlideshowWakeLock(_isPlaying);
      _syncSystemUi();
      if (_isTransitioning && _isPlaying) {
        _crossFadeController.forward();
      } else {
        _scheduleAdvance();
      }
      _scheduleControlsHide();
    } else {
      _setAlbumSlideshowWakeLock(false);
      _advanceTimer?.cancel();
      _controlsHideTimer?.cancel();
      _crossFadeController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _advanceTimer?.cancel();
    _controlsHideTimer?.cancel();
    _crossFadeAnimation.dispose();
    _crossFadeController.dispose();
    _setAlbumSlideshowWakeLock(false);
    _setSystemUiVisible(true);
    super.dispose();
  }

  void _syncSystemUi() => _setSystemUiVisible(_controlsVisible);

  void _setAlbumSlideshowWakeLock(bool enable) {
    if (_wakeLockRequested == enable) return;

    _wakeLockRequested = enable;
    wakeLockService.updateWakeLock(
      enable: enable,
      wakeLockFor: WakeLockFor.albumSlideshow,
    );
  }

  void _setSystemUiVisible(bool visible) {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        visible ? SystemUiMode.edgeToEdge : SystemUiMode.manual,
        overlays: visible ? SystemUiOverlay.values : const [],
      ),
    );
  }

  void _scheduleAdvance() {
    _advanceTimer?.cancel();
    if (!_isPlaying ||
        !_isForeground ||
        _isTransitioning ||
        _nextIndex == null) {
      return;
    }
    _advanceTimer = Timer(
      _isCurrentSlideReady ? _slideDuration : _mediaReadyTimeout,
      _advance,
    );
  }

  void _onSlideReady(int slotIndex, int index) {
    if (!mounted) return;

    final slot = _slots[slotIndex];
    if (slot.index != index || slot.isReady) return;

    slot.isReady = true;
    if (slotIndex == _currentSlotIndex) {
      _scheduleAdvance();
    }
  }

  void _advance() {
    if (!mounted ||
        _nextIndex == null ||
        _isTransitioning ||
        !_isPlaying ||
        !_isForeground) {
      return;
    }

    _advanceTimer?.cancel();
    _crossFadeController.forward(from: 0);
  }

  void _onCrossFadeStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final nextSlotIndex = _nextSlotIndex;
    final nextIndex = _slots[nextSlotIndex].index;
    if (nextIndex == null) return;

    setState(() {
      _currentSlotIndex = nextSlotIndex;
      _slots[_nextSlotIndex].index = _indexAfter(nextIndex);
      _crossFadeController.value = 0;
    });
    _scheduleAdvance();
  }

  void _togglePlayback() {
    setState(() {
      _isPlaying = !_isPlaying;
      _controlsVisible = true;
    });
    _syncSystemUi();
    _setAlbumSlideshowWakeLock(_isForeground && _isPlaying);
    if (_isPlaying) {
      if (_isTransitioning) {
        _crossFadeController.forward();
      } else {
        _scheduleAdvance();
      }
      _scheduleControlsHide();
    } else {
      _advanceTimer?.cancel();
      _controlsHideTimer?.cancel();
      _crossFadeController.stop();
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _syncSystemUi();
    if (_controlsVisible) {
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (!_isPlaying ||
        !_isForeground ||
        !_controlsVisible ||
        _accessibleNavigation) {
      return;
    }
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (!mounted || _accessibleNavigation) return;
      setState(() => _controlsVisible = false);
      _syncSystemUi();
    });
  }

  Widget _buildSlides() {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var slotIndex = 0; slotIndex < _slots.length; slotIndex++)
          if (_slots[slotIndex].index != null)
            _buildSlideSlot(
              slotIndex: slotIndex,
              index: _slots[slotIndex].index!,
              opacity: slotIndex == _currentSlotIndex
                  ? ReverseAnimation(_crossFadeAnimation)
                  : _crossFadeAnimation,
            ),
      ],
    );
  }

  Widget _buildSlideSlot({
    required int slotIndex,
    required int index,
    required Animation<double> opacity,
  }) {
    return IgnorePointer(
      child: FadeTransition(
        key: ValueKey("album-slideshow-slot-$slotIndex-opacity"),
        opacity: opacity,
        child: SizedBox.expand(
          key: ValueKey("album-slideshow-slot-$slotIndex-$index"),
          child: FileWidget(
            _files[index],
            tagPrefix: "album_slideshow_${slotIndex}_",
            backgroundDecoration: const BoxDecoration(),
            isFromMemories: true,
            onFinalFileLoad: ({required int memoryDuration}) =>
                _onSlideReady(slotIndex, index),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final mediaBackground = colors.specialScrim.withValues(alpha: 1);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: mediaBackground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildSlides(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
            ),
            _buildControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final colors = context.componentColors;
    return Theme(
      data: _controlsTheme,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colors.specialScrim.withValues(alpha: 0.72),
                        colors.specialScrim.withValues(alpha: 0.60),
                        colors.specialScrim.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.xs,
                        Spacing.lg,
                        Spacing.md,
                      ),
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: IconButtonComponent(
                                  tooltip: context.strings.close,
                                  variant: IconButtonComponentVariant.unfilled,
                                  shouldSurfaceExecutionStates: false,
                                  size: 48,
                                  onTap: () =>
                                      Navigator.maybePop(context).ignore(),
                                  icon: const HugeIcon(
                                    icon: HugeIcons.strokeRoundedCancel01,
                                    size: IconSizes.small,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Text(
                                widget.albumName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyles.display3.copyWith(
                                  color: colors.specialWhite,
                                ),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_files.length > 1)
                Center(child: _buildPlaybackButton(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackButton(BuildContext context) {
    final colors = context.componentColors;
    final label = _isPlaying
        ? context.strings.facesTimelinePlaybackPause
        : context.strings.facesTimelinePlaybackPlay;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.specialScrim.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: IconButtonComponent(
        tooltip: label,
        variant: IconButtonComponentVariant.unfilled,
        shouldSurfaceExecutionStates: false,
        size: 56,
        iconSize: IconSizes.medium,
        onTap: _togglePlayback,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: HugeIcon(
            key: ValueKey(_isPlaying),
            icon: _isPlaying
                ? HugeIcons.strokeRoundedPause
                : HugeIcons.strokeRoundedPlay,
            size: IconSizes.medium,
          ),
        ),
      ),
    );
  }
}
