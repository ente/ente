import "dart:async";
import "dart:ui";

import "package:ente_components/components/bottom_sheet/bottom_sheet_component.dart";
import "package:ente_components/components/buttons/icon_button_component.dart";
import "package:ente_components/components/filter_chip_component.dart";
import "package:ente_components/theme/icon_sizes.dart";
import "package:ente_components/theme/motion.dart";
import "package:ente_components/theme/spacing.dart";
import "package:ente_components/theme/text_styles.dart";
import "package:ente_components/theme/theme.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/viewer/file/file_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

const _albumSlideshowDurationOptions = [5, 10, 15, 30];

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

class _AlbumSlideshowPageState extends State<AlbumSlideshowPage>
    with WidgetsBindingObserver {
  static const Duration _mediaReadyTimeout = Duration(seconds: 10);
  static const Duration _autoCrossFadeDuration = Duration(milliseconds: 600);
  static const Duration _manualCrossFadeDuration = Duration(milliseconds: 200);
  static const Duration _backgroundCrossFadeDuration = Duration(
    milliseconds: 750,
  );
  static const Duration _controlsHideDelay = Duration(seconds: 3);
  static final ThemeData _controlsTheme = ComponentTheme.darkTheme();

  Timer? _advanceTimer;
  Timer? _controlsHideTimer;
  late List<EnteFile> _files;
  late Duration _slideDuration;
  int _currentIndex = 0;
  bool _currentSlideReady = false;
  bool _autoAdvanceTransition = false;
  late bool _useBlurredBackground;
  late bool _useRandomOrder;
  bool _controlsVisible = true;
  bool _isPlaying = true;
  bool _isSettingsOpen = false;
  bool _accessibleNavigation = false;
  bool _wakeLockRequested = false;

  EnteFile get _currentFile => _files[_currentIndex];
  bool get _isForeground =>
      (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
      AppLifecycleState.resumed;
  bool get _canAdvance =>
      _isPlaying && _isForeground && !_isSettingsOpen && _files.length > 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slideDuration = Duration(
      seconds: localSettings.albumSlideshowDurationSeconds,
    );
    _useBlurredBackground = localSettings.albumSlideshowBlurredBackground;
    _useRandomOrder = localSettings.albumSlideshowRandomOrder;
    _files = List.of(widget.files);
    if (_useRandomOrder) {
      _files.shuffle();
    }
    _setAlbumSlideshowWakeLock(_isForeground && _isPlaying);
    _preloadAdjacentFiles();
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
    if (state == AppLifecycleState.resumed) {
      _setAlbumSlideshowWakeLock(_isPlaying && !_isSettingsOpen);
      _syncSystemUi();
      _scheduleAdvance();
      _scheduleControlsHide();
    } else {
      _setAlbumSlideshowWakeLock(false);
      _cancelAdvanceTimer();
      _controlsHideTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAdvanceTimer();
    _controlsHideTimer?.cancel();
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
    _cancelAdvanceTimer();
    if (!_canAdvance) return;

    _advanceTimer = Timer(
      _currentSlideReady ? _slideDuration : _mediaReadyTimeout,
      () {
        _advanceTimer = null;
        _goToNext(autoAdvance: true);
      },
    );
  }

  void _cancelAdvanceTimer() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
  }

  void _onSlideReady(String fileTag) {
    if (!mounted || fileTag != _currentFile.tag || _currentSlideReady) return;

    _currentSlideReady = true;
    _scheduleAdvance();
  }

  void _goToNext({required bool autoAdvance}) {
    if (autoAdvance && !_canAdvance) return;
    _goToIndex((_currentIndex + 1) % _files.length, autoAdvance: autoAdvance);
  }

  void _goToPrevious() {
    _goToIndex(
      (_currentIndex - 1 + _files.length) % _files.length,
      autoAdvance: false,
    );
  }

  void _goToIndex(int index, {required bool autoAdvance}) {
    if (!mounted || _files.length < 2 || index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
      _currentSlideReady = false;
      _autoAdvanceTransition = autoAdvance;
    });
    _preloadAdjacentFiles();
    _scheduleAdvance();
  }

  void _preloadAdjacentFiles() {
    if (_files.length < 2) return;

    final previousIndex = (_currentIndex - 1 + _files.length) % _files.length;
    final nextIndex = (_currentIndex + 1) % _files.length;
    _preloadFileAt(previousIndex);
    if (nextIndex != previousIndex) {
      _preloadFileAt(nextIndex);
    }
  }

  void _preloadFileAt(int index) {
    preloadThumbnail(_files[index]);
    preloadFile(_files[index]);
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _cancelAdvanceTimer();
    }
    setState(() {
      _isPlaying = !_isPlaying;
      _controlsVisible = true;
    });
    _syncSystemUi();
    _setAlbumSlideshowWakeLock(_isForeground && _isPlaying && !_isSettingsOpen);
    if (_isPlaying) {
      _scheduleAdvance();
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _setSlideDuration(int seconds) {
    if (_slideDuration.inSeconds == seconds) return;

    setState(() => _slideDuration = Duration(seconds: seconds));
    unawaited(localSettings.setAlbumSlideshowDurationSeconds(seconds));
    if (_currentSlideReady) {
      _scheduleAdvance();
    }
  }

  void _setBlurredBackground(bool value) {
    if (_useBlurredBackground == value) return;

    setState(() => _useBlurredBackground = value);
    unawaited(localSettings.setAlbumSlideshowBlurredBackground(value));
  }

  void _setRandomOrder(bool value) {
    if (_useRandomOrder == value) return;

    final currentFile = _currentFile;
    final files = List<EnteFile>.of(widget.files);
    if (value) {
      files.shuffle();
    }
    setState(() {
      _files = files;
      _currentIndex = files.indexOf(currentFile);
      _useRandomOrder = value;
    });
    _preloadAdjacentFiles();
    unawaited(localSettings.setAlbumSlideshowRandomOrder(value));
  }

  Future<void> _showSettings() async {
    if (_isSettingsOpen) return;

    _cancelAdvanceTimer();
    _controlsHideTimer?.cancel();
    setState(() {
      _isSettingsOpen = true;
      _controlsVisible = true;
    });
    _syncSystemUi();
    _setAlbumSlideshowWakeLock(false);

    await showBottomSheetComponent<void>(
      context: context,
      builder: (_) => Theme(
        data: _controlsTheme,
        child: _AlbumSlideshowSettingsSheet(
          initialDurationSeconds: _slideDuration.inSeconds,
          initiallyRandomOrder: _useRandomOrder,
          initiallyBlurred: _useBlurredBackground,
          onDurationSelected: _setSlideDuration,
          onRandomOrderChanged: _setRandomOrder,
          onBlurredBackgroundChanged: _setBlurredBackground,
        ),
      ),
    );
    if (!mounted) return;

    setState(() => _isSettingsOpen = false);
    _setAlbumSlideshowWakeLock(_isForeground && _isPlaying);
    _syncSystemUi();
    _scheduleAdvance();
    _scheduleControlsHide();
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
        _isSettingsOpen ||
        _accessibleNavigation) {
      return;
    }
    _controlsHideTimer = Timer(_controlsHideDelay, () {
      if (!mounted || _accessibleNavigation) return;
      setState(() => _controlsVisible = false);
      _syncSystemUi();
    });
  }

  void _handleTap(TapUpDetails details) {
    if (_files.length < 2) {
      _toggleControls();
      return;
    }

    final width = MediaQuery.sizeOf(context).width;
    if (details.localPosition.dx < width * 0.25) {
      HapticFeedback.selectionClick();
      _goToPrevious();
    } else if (details.localPosition.dx > width * 0.75) {
      HapticFeedback.selectionClick();
      _goToNext(autoAdvance: false);
    } else {
      _toggleControls();
    }
  }

  Widget _buildBackground() {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: _backgroundCrossFadeDuration,
        switchInCurve: Curves.easeOutExpo,
        switchOutCurve: Curves.easeInExpo,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        child: _useBlurredBackground
            ? ImageFiltered(
                key: ValueKey("album-slideshow-blur-${_currentFile.tag}"),
                imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: ThumbnailWidget(
                  _currentFile,
                  placeholderColor: Colors.black,
                  shouldShowSyncStatus: false,
                  shouldShowFavoriteIcon: false,
                  shouldShowVideoOverlayIcon: false,
                ),
              )
            : const ColoredBox(
                key: ValueKey("album-slideshow-black-background"),
                color: Colors.black,
              ),
      ),
    );
  }

  Widget _buildSlide() {
    final file = _currentFile;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: _autoAdvanceTransition
            ? _autoCrossFadeDuration
            : _manualCrossFadeDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [
            for (final child in previousChildren)
              HeroMode(enabled: false, child: child),
            ?currentChild,
          ],
        ),
        child: SizedBox.expand(
          key: ValueKey("album-slideshow-${file.tag}"),
          child: FileWidget(
            file,
            tagPrefix: "album_slideshow",
            backgroundDecoration: const BoxDecoration(),
            isFromMemories: true,
            onFinalFileLoad: ({required int memoryDuration}) =>
                _onSlideReady(file.tag),
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
            _buildBackground(),
            _buildSlide(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTap,
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
                            SizedBox(
                              width: 48,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: IconButtonComponent(
                                  tooltip: pendingTranslation(
                                    "Slideshow settings",
                                  ),
                                  variant: IconButtonComponentVariant.unfilled,
                                  shouldSurfaceExecutionStates: false,
                                  size: 48,
                                  onTap: _showSettings,
                                  icon: const HugeIcon(
                                    icon: HugeIcons.strokeRoundedSettings01,
                                    size: IconSizes.small,
                                  ),
                                ),
                              ),
                            ),
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

class _AlbumSlideshowSettingsSheet extends StatefulWidget {
  const _AlbumSlideshowSettingsSheet({
    required this.initialDurationSeconds,
    required this.initiallyRandomOrder,
    required this.initiallyBlurred,
    required this.onDurationSelected,
    required this.onRandomOrderChanged,
    required this.onBlurredBackgroundChanged,
  });

  final int initialDurationSeconds;
  final bool initiallyRandomOrder;
  final bool initiallyBlurred;
  final ValueChanged<int> onDurationSelected;
  final ValueChanged<bool> onRandomOrderChanged;
  final ValueChanged<bool> onBlurredBackgroundChanged;

  @override
  State<_AlbumSlideshowSettingsSheet> createState() =>
      _AlbumSlideshowSettingsSheetState();
}

class _AlbumSlideshowSettingsSheetState
    extends State<_AlbumSlideshowSettingsSheet> {
  late int _durationSeconds;
  late bool _randomOrder;
  late bool _blurred;

  @override
  void initState() {
    super.initState();
    _durationSeconds = widget.initialDurationSeconds;
    _randomOrder = widget.initiallyRandomOrder;
    _blurred = widget.initiallyBlurred;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: pendingTranslation("Slideshow settings"),
      closeTooltip: context.strings.close,
      isScrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pendingTranslation("Slide duration"),
            style: TextStyles.bodyBold.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.md,
            children: [
              for (final seconds in _albumSlideshowDurationOptions)
                _buildChip(
                  label: pendingTranslation("$seconds sec"),
                  selected: seconds == _durationSeconds,
                  onTap: () {
                    if (seconds == _durationSeconds) return;
                    setState(() => _durationSeconds = seconds);
                    widget.onDurationSelected(seconds);
                  },
                ),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            pendingTranslation("Order"),
            style: TextStyles.bodyBold.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.md,
            children: [
              _buildChip(
                label: pendingTranslation("In order"),
                selected: !_randomOrder,
                onTap: () => _setRandomOrder(false),
              ),
              _buildChip(
                label: pendingTranslation("Random"),
                selected: _randomOrder,
                onTap: () => _setRandomOrder(true),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            pendingTranslation("Background"),
            style: TextStyles.bodyBold.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.md,
            children: [
              _buildChip(
                label: pendingTranslation("Blurred"),
                selected: _blurred,
                onTap: () => _setBlurred(true),
              ),
              _buildChip(
                label: pendingTranslation("Black"),
                selected: !_blurred,
                onTap: () => _setBlurred(false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedSize(
      duration: Motion.standard,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.centerLeft,
      child: FilterChipComponent(
        label: label,
        state: selected
            ? FilterChipComponentState.selected
            : FilterChipComponentState.unselected,
        trailing: selected
            ? const HugeIcon(icon: HugeIcons.strokeRoundedTick02, size: 12)
            : null,
        onChanged: (_) => onTap(),
      ),
    );
  }

  void _setBlurred(bool value) {
    if (_blurred == value) return;

    setState(() => _blurred = value);
    widget.onBlurredBackgroundChanged(value);
  }

  void _setRandomOrder(bool value) {
    if (_randomOrder == value) return;

    setState(() => _randomOrder = value);
    widget.onRandomOrderChanged(value);
  }
}
