import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:audio_session/audio_session.dart";
import "package:ente_components/theme/colors.dart" as components;
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:intl/intl.dart";
import "package:just_audio/just_audio.dart";
import "package:logging/logging.dart";
import "package:mesh_gradient/mesh_gradient.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/services/wrapped/models.dart";
import "package:photos/services/wrapped/wrapped_media_preloader.dart";
import "package:photos/services/wrapped/wrapped_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/file/zoomable_image.dart";
import "package:photos/utils/share_util.dart";
import "package:share_plus/share_plus.dart";

part "cards/story_card.dart";
part "cards/stats_card_content.dart";
part "cards/people_card_content.dart";
part "cards/places_card_content.dart";
part "cards/aesthetics_card_content.dart";
part "cards/curation_card_content.dart";
part "cards/narrative_card_content.dart";
part "cards/badge_card_content.dart";
part "cards/shared_widgets.dart";

const double _kStoryCardOuterHorizontalInset = 18.0;
const double _kStoryCardOuterVerticalInset = 12.0;
const double _kStoryCardInnerHorizontalPadding = 24.0;
const double _kStoryCardInnerTopPadding = 28.0;
const double _kStoryCardInnerBottomPadding = 32.0;

const EdgeInsets _kStoryCardOuterPadding = EdgeInsets.symmetric(
  horizontal: _kStoryCardOuterHorizontalInset,
  vertical: _kStoryCardOuterVerticalInset,
);

const EdgeInsets _kStoryCardInnerPadding = EdgeInsets.fromLTRB(
  _kStoryCardInnerHorizontalPadding,
  _kStoryCardInnerTopPadding,
  _kStoryCardInnerHorizontalPadding,
  _kStoryCardInnerBottomPadding,
);

const double _kStoryDesignWidth = 380.0;
const double _kStoryDesignHeight = 700.0;
const double _kStoryControlReserveHeight = 72.0;
const double _kStoryControlBottomPadding = 8.0;

const double _kStoryControlSize = 48.0;
const double _kStoryControlIconSize = 24.0;
const double _kStoryControlHorizontalMarginFromEdge =
    _kStoryCardOuterHorizontalInset + _kStoryCardInnerHorizontalPadding;
const double _kStoryControlBottomMarginFromEdge = _kStoryCardOuterVerticalInset;

/// Basic viewer for the stats-only Ente Rewind experience.
class WrappedViewerPage extends StatefulWidget {
  const WrappedViewerPage({required this.initialState, super.key});

  final WrappedEntryState initialState;

  @override
  State<WrappedViewerPage> createState() => _WrappedViewerPageState();
}

class _WrappedViewerPageState extends State<WrappedViewerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late PageController _pageController;
  late AnimationController _progressController;
  late WrappedEntryState _state;
  late List<WrappedCard> _cards;
  late int _currentIndex;
  bool _isPaused = false;
  VoidCallback? _stateListener;
  final GlobalKey _shareButtonKey = GlobalKey();
  final GlobalKey _cardBoundaryKey = GlobalKey();
  final Logger _logger = Logger("WrappedViewerPage");
  bool _pendingRestart = false;
  bool _suppressNextTapUp = false;
  bool _longPressActive = false;
  bool _wasPausedBeforeLongPress = false;
  double _verticalDragDistance = 0;
  bool _isClosing = false;
  ui.Image? _shareBrandingLogo;
  late final AudioPlayer _audioPlayer;
  bool _isMusicReady = false;
  bool _isMusicMuted = false;
  bool _isMusicPlaying = false;
  bool _musicLoadFailed = false;
  bool _isFadingOutMusic = false;
  bool _hideBadgeSharePill = false;
  OverlayEntry? _sharePillOverlayEntry;
  ui.Image? _sharePillOverlaySnapshot;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Future<void>? _musicInitializationFuture;
  ModalRoute<dynamic>? _registeredRoute;
  bool _didRegisterWillPop = false;
  static bool _audioSessionConfigured = false;
  EnteFile? _previewFile;
  bool _isPreviewVisible = false;
  bool _isPreviewLoading = false;
  bool _wasPausedBeforePreview = false;
  int _previewRequestID = 0;
  int? _previewUploadedFileID;

  static const double _kShareBrandingHeight = 42;
  static const double _kShareBrandingLogoWidth = 58;
  static const double _kShareBrandingLogoHeight = 11;
  static const double _kShareBrandingLogoVerticalNudge = -8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = widget.initialState;
    _cards = _buildCards(_state.result?.cards);
    final int initialPage = _initialPageForState(_state);
    _currentIndex = initialPage;
    _pageController = PageController(initialPage: initialPage);
    _progressController = AnimationController(
      vsync: this,
      duration: _durationForCard(_currentIndex),
    )..addStatusListener(_handleProgressStatus);
    if (_cards.isNotEmpty) {
      _progressController.forward();
    }
    _stateListener = () => _handleServiceUpdate(wrappedService.state);
    wrappedService.stateListenable.addListener(_stateListener!);
    _audioPlayer = AudioPlayer();
    _playerStateSubscription = _audioPlayer.playerStateStream.listen(
      _handlePlayerState,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ModalRoute<dynamic>? route = ModalRoute.of(context);
      if (route == null) {
        return;
      }
      // ignore: deprecated_member_use
      route.addScopedWillPopCallback(_handleWillPop);
      _registeredRoute = route;
      _didRegisterWillPop = true;
    });
    unawaited(_initBackgroundMusic());
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.rewindViewer,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_stateListener != null) {
      wrappedService.stateListenable.removeListener(_stateListener!);
    }
    _removeSharePillOverlay();
    if (_didRegisterWillPop && _registeredRoute != null) {
      // ignore: deprecated_member_use
      _registeredRoute!.removeScopedWillPopCallback(_handleWillPop);
      _didRegisterWillPop = false;
      _registeredRoute = null;
    }
    _progressController.removeStatusListener(_handleProgressStatus);
    _progressController.dispose();
    _pageController.dispose();
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_audioPlayer.dispose());
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.rewindViewer,
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _syncMusicPlayback();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_fadeOutAndStopMusic());
        break;
    }
  }

  int _initialPageForState(WrappedEntryState state) {
    final int cardCount = _cards.length;
    if (cardCount <= 1) {
      return 0;
    }
    final int lastIndex = cardCount - 1;
    if (state.isComplete && state.resumeIndex >= lastIndex) {
      return 0;
    }
    return state.resumeIndex.clamp(0, lastIndex);
  }

  void _handleServiceUpdate(WrappedEntryState next) {
    if (!mounted) {
      return;
    }
    setState(() {
      _state = next;
      _cards = _buildCards(next.result?.cards);
    });
    final int newCardCount = _cards.length;
    _syncMusicPlayback();
    if (newCardCount == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_currentIndex >= newCardCount) {
      unawaited(
        _goToIndex(newCardCount - 1, restartProgress: false, animate: false),
      );
    } else {
      _configureForCurrentCard(restartProgress: false);
    }
  }

  List<WrappedCard> _buildCards(List<WrappedCard>? source) {
    if (source == null || source.isEmpty) {
      return <WrappedCard>[];
    }
    final List<WrappedCard> cards = List<WrappedCard>.from(source);
    if (!kDebugMode) {
      return cards;
    }

    WrappedCard? badgeCard;
    for (final WrappedCard card in cards) {
      if (card.type == WrappedCardType.badge) {
        badgeCard = card;
        break;
      }
    }
    if (badgeCard == null) {
      return cards;
    }

    final Object? rawCandidates = badgeCard.meta["candidates"];
    if (rawCandidates is! List || rawCandidates.isEmpty) {
      return cards;
    }

    final List<Map<String, Object?>> candidates = rawCandidates
        .whereType<Map>()
        .map((Map<dynamic, dynamic> entry) => entry.cast<String, Object?>())
        .toList(growable: false);
    if (candidates.isEmpty) {
      return cards;
    }

    final String? primaryBadgeKey = badgeCard.meta["badgeKey"] as String?;
    final int badgeIndex = cards.indexOf(badgeCard);
    final int insertionIndex = badgeIndex >= 0 ? badgeIndex + 1 : cards.length;
    final List<WrappedCard> previewCards = <WrappedCard>[];

    for (final Map<String, Object?> candidate in candidates) {
      final String? candidateKey = candidate["key"] as String?;
      if (candidateKey == null) {
        continue;
      }
      if (candidateKey == primaryBadgeKey) {
        continue;
      }

      final Map<String, Object?> meta = Map<String, Object?>.from(candidate)
        ..["badgeKey"] = candidateKey;
      final List<int> uploadedIDs =
          (meta.remove("uploadedFileIDs") as List<dynamic>?)
              ?.map(
                (dynamic value) =>
                    value is num ? value.toInt() : int.tryParse("$value"),
              )
              .whereType<int>()
              .where((int id) => id > 0)
              .toList(growable: false) ??
          const <int>[];
      final List<MediaRef> mediaRefs = uploadedIDs.isNotEmpty
          ? uploadedIDs.map(MediaRef.new).toList(growable: false)
          : badgeCard.media;

      final String? candidateTitle = (meta.remove("title") as String?)?.trim();
      final String title = (candidateTitle != null && candidateTitle.isNotEmpty)
          ? candidateTitle
          : badgeCard.title;
      final String? candidateSubtitle = (meta.remove("subtitle") as String?)
          ?.trim();
      final String? subtitleValue =
          (candidateSubtitle != null && candidateSubtitle.isNotEmpty)
          ? candidateSubtitle
          : badgeCard.subtitle;

      meta["uploadedFileIDs"] = uploadedIDs;
      meta["detailChips"] ??= badgeCard.meta["detailChips"];
      meta["gradient"] ??= badgeCard.meta["gradient"];
      meta["emoji"] ??= badgeCard.meta["emoji"];
      meta["debugPreview"] = true;

      previewCards.add(
        WrappedCard(
          type: WrappedCardType.badge,
          title: title,
          subtitle: subtitleValue,
          media: mediaRefs,
          meta: meta,
        ),
      );
    }

    if (previewCards.isNotEmpty) {
      cards.insertAll(insertionIndex, previewCards);
    }

    cards.add(
      WrappedCard(
        type: WrappedCardType.badgeDebug,
        title: "Badge candidates (debug)",
        meta: <String, Object?>{
          "candidates": candidates,
          "badgeKey": badgeCard.meta["badgeKey"],
          "displayDurationMillis": 12000,
        },
      ),
    );

    return cards;
  }

  void _handleProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    if (_currentIndex >= _cards.length - 1) {
      wrappedService.markComplete();
      _pauseAutoplay();
      return;
    }
    unawaited(_goToIndex(_currentIndex + 1));
  }

  Duration _durationForCard(int index) {
    if (_cards.isEmpty || index < 0 || index >= _cards.length) {
      return const Duration(seconds: 5);
    }
    final WrappedCard card = _cards[index];
    final Object? durationMeta = card.meta["displayDurationMillis"];
    final int durationMillis = durationMeta is num
        ? durationMeta.clamp(1500, 20000).toInt()
        : 6000;
    return Duration(milliseconds: durationMillis);
  }

  void _configureForCurrentCard({required bool restartProgress}) {
    _progressController.duration = _durationForCard(_currentIndex);
    if (restartProgress) {
      _progressController
        ..stop()
        ..reset();
      if (!_isPaused) {
        _progressController.forward();
      }
    }
  }

  Future<void> _goToIndex(
    int index, {
    bool restartProgress = true,
    bool animate = true,
  }) async {
    if (index < 0 || index >= _cards.length) {
      return;
    }
    _pendingRestart = restartProgress;
    if (!_pageController.hasClients) {
      _pendingRestart = false;
      _updateCurrentIndex(index, restartProgress: restartProgress);
      return;
    }
    if (animate) {
      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.jumpToPage(index);
    }
    if (!_pendingRestart) {
      // If no restart requested, ensure service sync still happens.
      _updateCurrentIndex(index, restartProgress: false);
    }
  }

  void _handlePageChanged(int index) {
    _pendingRestart = false;
    _updateCurrentIndex(index, restartProgress: true);
  }

  void _updateCurrentIndex(int index, {required bool restartProgress}) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
    });
    wrappedService.updateResumeIndex(index);
    final int lastIndex = _cards.length - 1;
    if (index == lastIndex) {
      wrappedService.markComplete();
    }
    _configureForCurrentCard(restartProgress: restartProgress);
  }

  void _pauseAutoplay() {
    if (_isPaused) return;
    _isPaused = true;
    _progressController.stop();
  }

  void _resumeAutoplay() {
    if (!_isPaused) return;
    _isPaused = false;
    _progressController.forward();
  }

  void _togglePause() {
    if (_isPaused) {
      _resumeAutoplay();
    } else {
      _pauseAutoplay();
    }
  }

  void _handleTap(Offset localPosition, BoxConstraints constraints) {
    final double dx = localPosition.dx;
    final double width = constraints.maxWidth;
    final double leftZoneBoundary = width * 0.25;
    final double rightZoneBoundary = width * 0.75;
    _triggerLightHaptic();
    if (dx < leftZoneBoundary) {
      if (_progressController.value > 0.1) {
        _configureForCurrentCard(restartProgress: true);
      } else {
        unawaited(_goToIndex(_currentIndex - 1, animate: false));
      }
    } else if (dx > rightZoneBoundary) {
      unawaited(_goToIndex(_currentIndex + 1, animate: false));
    } else {
      _togglePause();
      setState(() {});
    }
  }

  void _handleTapUp(TapUpDetails details, BoxConstraints constraints) {
    if (_suppressNextTapUp) {
      _suppressNextTapUp = false;
      return;
    }
    _handleTap(details.localPosition, constraints);
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _verticalDragDistance = 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isClosing) {
      return;
    }
    final double? delta = details.primaryDelta;
    if (delta == null || delta <= 0) {
      return;
    }
    _verticalDragDistance += delta;
    if (_verticalDragDistance >= 100) {
      unawaited(_closeViewer());
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isClosing) {
      return;
    }
    final double velocity = details.primaryVelocity ?? 0;
    if (_verticalDragDistance >= 60 || velocity > 800) {
      unawaited(_closeViewer());
    }
    _verticalDragDistance = 0;
  }

  void _handleVerticalDragCancel() {
    _verticalDragDistance = 0;
  }

  Future<void> _closeViewer() async {
    if (_isPreviewVisible) {
      _hideMediaPreview();
      return;
    }
    if (_isClosing || !mounted) {
      return;
    }
    _isClosing = true;
    if (!_didRegisterWillPop) {
      await _fadeOutAndStopMusic();
    }
    if (!mounted) return;
    final bool didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      _isClosing = false;
    }
  }

  Future<bool> _handleWillPop() async {
    if (_isPreviewVisible) {
      _hideMediaPreview();
      return false;
    }
    if (!_isClosing) {
      _isClosing = true;
    }
    await _fadeOutAndStopMusic();
    return true;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (_longPressActive) {
      return;
    }
    _longPressActive = true;
    _suppressNextTapUp = true;
    _wasPausedBeforeLongPress = _isPaused;
    _triggerLightHaptic();
    _pauseAutoplay();
    setState(() {});
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (!_longPressActive) {
      return;
    }
    _longPressActive = false;
    if (!_wasPausedBeforeLongPress) {
      _resumeAutoplay();
    }
    _wasPausedBeforeLongPress = false;
    _scheduleTapUpReset();
    setState(() {});
  }

  void _handleLongPressCancel() {
    if (!_longPressActive) {
      return;
    }
    _longPressActive = false;
    if (!_wasPausedBeforeLongPress) {
      _resumeAutoplay();
    }
    _wasPausedBeforeLongPress = false;
    _scheduleTapUpReset();
    setState(() {});
  }

  void _showMediaPreview(MediaRef ref) {
    if (_isPreviewVisible &&
        _previewUploadedFileID == ref.uploadedFileID &&
        _previewFile != null) {
      return;
    }
    final int requestID = ++_previewRequestID;
    final bool wasPaused = _isPaused;
    if (!wasPaused) {
      _pauseAutoplay();
    }
    final EnteFile? cached = WrappedMediaPreloader.instance.getCachedFile(
      ref.uploadedFileID,
    );
    setState(() {
      _previewUploadedFileID = ref.uploadedFileID;
      _previewFile = cached;
      _isPreviewVisible = true;
      _isPreviewLoading = cached == null;
      _wasPausedBeforePreview = wasPaused;
    });
    if (cached != null) {
      return;
    }
    WrappedMediaPreloader.instance
        .ensureFile(ref.uploadedFileID)
        .then(
          (EnteFile? file) {
            if (!mounted || requestID != _previewRequestID) {
              return;
            }
            setState(() {
              _previewFile = file;
              _isPreviewLoading = false;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted || requestID != _previewRequestID) {
              return;
            }
            _logger.warning("Unable to load preview media", error, stackTrace);
            setState(() {
              _previewFile = null;
              _isPreviewLoading = false;
            });
          },
        );
  }

  void _hideMediaPreview() {
    if (!_isPreviewVisible) {
      return;
    }
    _previewRequestID++;
    final bool shouldResume = !_wasPausedBeforePreview;
    _wasPausedBeforePreview = false;
    setState(() {
      _previewFile = null;
      _isPreviewVisible = false;
      _isPreviewLoading = false;
      _previewUploadedFileID = null;
    });
    if (shouldResume) {
      _resumeAutoplay();
    }
  }

  void _handlePreviewTapDown() {
    _suppressNextTapUp = true;
  }

  void _handlePreviewTapCancel() {
    _suppressNextTapUp = false;
  }

  void _scheduleTapUpReset() {
    scheduleMicrotask(() {
      _suppressNextTapUp = false;
    });
  }

  void _triggerLightHaptic() {
    unawaited(HapticFeedback.lightImpact());
  }

  @override
  Widget build(BuildContext context) {
    final WrappedResult? result = _state.result;
    final int cardCount = _cards.length;
    if (result == null || cardCount == 0) {
      scheduleMicrotask(() {
        if (mounted) {
          showShortToast(context, "Ente Rewind data not available");
          Navigator.of(context).maybePop();
        }
      });
      return const SizedBox.shrink();
    }

    final bool isCurrentCardBadge =
        _cards[_currentIndex].type == WrappedCardType.badge ||
        _cards[_currentIndex].type == WrappedCardType.badgeDebug;

    return Theme(
      data: darkThemeData,
      child: Builder(
        builder: (BuildContext context) {
          final MediaQueryData baseMediaQuery = MediaQuery.of(context);
          final MediaQueryData clampedMediaQuery = baseMediaQuery.copyWith(
            textScaler: const TextScaler.linear(1.0),
          );
          return MediaQuery(
            data: clampedMediaQuery,
            child: Builder(
              builder: (BuildContext context) {
                final enteColorScheme = getEnteColorScheme(context);
                final textTheme = getEnteTextTheme(context);
                final MediaQueryData mediaQuery = MediaQuery.of(context);
                final double bottomPadding = mediaQuery.padding.bottom;
                final Color controlIconColor = enteColorScheme.textMuted
                    .withValues(alpha: 0.62);
                final Color controlBackdropColor = enteColorScheme.textMuted
                    .withValues(alpha: 0.14);

                return PopScope(
                  canPop: true,
                  onPopInvokedWithResult: (bool didPop, Object? result) {
                    if (!didPop) {
                      _isClosing = false;
                      return;
                    }
                    wrappedService.updateResumeIndex(_currentIndex);
                  },
                  child: Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(
                      leading: BackButton(
                        onPressed: () => unawaited(_closeViewer()),
                      ),
                      title: Text("Ente Rewind", style: textTheme.largeBold),
                      backgroundColor: Colors.black,
                      foregroundColor: enteColorScheme.textBase,
                      elevation: 0,
                    ),
                    body: Stack(
                      children: [
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: IgnorePointer(
                                child: AnimatedBuilder(
                                  animation: _progressController,
                                  builder: (BuildContext context, _) {
                                    final List<double> segments =
                                        List<double>.generate(cardCount, (
                                          int index,
                                        ) {
                                          if (index < _currentIndex) {
                                            return 1.0;
                                          }
                                          if (index > _currentIndex) {
                                            return 0.0;
                                          }
                                          return _progressController.value
                                              .clamp(0.0, 1.0);
                                        });
                                    return _StoryProgressBar(
                                      progressValues: segments,
                                      colorScheme: enteColorScheme,
                                    );
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder:
                                    (
                                      BuildContext context,
                                      BoxConstraints constraints,
                                    ) {
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapUp: (TapUpDetails details) =>
                                            _handleTapUp(details, constraints),
                                        onTapCancel: () {
                                          _suppressNextTapUp = false;
                                        },
                                        onLongPressStart: _handleLongPressStart,
                                        onLongPressEnd: _handleLongPressEnd,
                                        onLongPressCancel:
                                            _handleLongPressCancel,
                                        onVerticalDragStart:
                                            _handleVerticalDragStart,
                                        onVerticalDragUpdate:
                                            _handleVerticalDragUpdate,
                                        onVerticalDragEnd:
                                            _handleVerticalDragEnd,
                                        onVerticalDragCancel:
                                            _handleVerticalDragCancel,
                                        child: RepaintBoundary(
                                          key: _cardBoundaryKey,
                                          child: _MediaPreviewController(
                                            onPreviewStart: _showMediaPreview,
                                            onPreviewTapDown:
                                                _handlePreviewTapDown,
                                            onPreviewTapCancel:
                                                _handlePreviewTapCancel,
                                            child: PageView.builder(
                                              physics:
                                                  const PageScrollPhysics(),
                                              controller: _pageController,
                                              onPageChanged: _handlePageChanged,
                                              itemCount: cardCount,
                                              itemBuilder:
                                                  (
                                                    BuildContext context,
                                                    int index,
                                                  ) {
                                                    final WrappedCard card =
                                                        _cards[index];
                                                    return _StoryCard(
                                                      card: card,
                                                      colorScheme:
                                                          enteColorScheme,
                                                      textTheme: textTheme,
                                                      isActive:
                                                          index ==
                                                          _currentIndex,
                                                      gradientVariantIndex:
                                                          index,
                                                    );
                                                  },
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ],
                        ),
                        if (!isCurrentCardBadge) ...[
                          Positioned(
                            right: _kStoryControlHorizontalMarginFromEdge,
                            bottom:
                                bottomPadding +
                                _kStoryControlBottomMarginFromEdge,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  key: _shareButtonKey,
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _handleShare,
                                  child: Container(
                                    width: _kStoryControlSize,
                                    height: _kStoryControlSize,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: controlBackdropColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.share,
                                      size: _kStoryControlIconSize,
                                      color: controlIconColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  height: _kStoryControlBottomPadding,
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: _kStoryControlHorizontalMarginFromEdge,
                            bottom:
                                bottomPadding +
                                _kStoryControlBottomMarginFromEdge,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => unawaited(_handleMusicToggle()),
                                  child: Container(
                                    width: _kStoryControlSize,
                                    height: _kStoryControlSize,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: controlBackdropColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      (_isMusicMuted || !_isMusicPlaying)
                                          ? Icons.volume_off
                                          : Icons.volume_up,
                                      size: _kStoryControlIconSize,
                                      color: controlIconColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                  height: _kStoryControlBottomPadding,
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_isPreviewVisible)
                          Positioned.fill(
                            child: _MediaPreviewOverlay(
                              file: _previewFile,
                              isLoading: _isPreviewLoading,
                              onDismiss: _hideMediaPreview,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  GlobalKey get shareButtonKey => _shareButtonKey;
  bool get hideBadgeSharePill => _hideBadgeSharePill;

  Future<void> shareCurrentCard() async {
    await _handleShare();
  }

  Future<void> _handleShare() async {
    if (_cards.isEmpty) {
      showShortToast(context, "Nothing to share yet");
      return;
    }
    final WrappedCard currentCard = _cards[_currentIndex];
    final bool shouldShowBranding = _shouldShowBrandingForCard(currentCard);
    final bool wasPaused = _isPaused;
    _pauseAutoplay();
    try {
      final bool hideShareControls =
          currentCard.type == WrappedCardType.badge ||
          currentCard.type == WrappedCardType.badgeDebug;
      final Uint8List? bytes = await _captureCurrentCard(
        includeBranding: shouldShowBranding,
        hideInteractiveControls: hideShareControls,
      );
      if (bytes == null) {
        if (!mounted) return;
        showShortToast(context, "Unable to prepare share");
        return;
      }
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              bytes,
              name: "ente_rewind_${_currentIndex + 1}.png",
              mimeType: "image/png",
            ),
          ],
          sharePositionOrigin: shareButtonRect(context, _shareButtonKey),
        ),
      );
    } catch (error, stackTrace) {
      _logger.severe("Failed to share Ente Rewind card", error, stackTrace);
      if (mounted) {
        showShortToast(context, "Share failed");
      }
    } finally {
      if (!wasPaused) {
        _resumeAutoplay();
      }
    }
  }

  Future<Uint8List?> _captureCurrentCard({
    required bool includeBranding,
    bool hideInteractiveControls = false,
  }) async {
    Future<void> showShareControlsIfHidden() async {
      bool awaitedFrame = false;
      if (_hideBadgeSharePill && mounted) {
        setState(() {
          _hideBadgeSharePill = false;
        });
        awaitedFrame = true;
      }
      if (awaitedFrame) {
        await WidgetsBinding.instance.endOfFrame;
      }
      _removeSharePillOverlay();
    }

    if (hideInteractiveControls && !_hideBadgeSharePill && mounted) {
      await _showSharePillOverlay();
      if (!_hideBadgeSharePill && mounted) {
        setState(() {
          _hideBadgeSharePill = true;
        });
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    await Future<void>.delayed(Duration.zero);
    final RenderRepaintBoundary? boundary =
        _cardBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      await showShareControlsIfHidden();
      return null;
    }
    final double logicalWidth = boundary.size.width;
    if (logicalWidth <= 0) {
      await showShareControlsIfHidden();
      return null;
    }
    final double pixelRatio = (1080 / logicalWidth).clamp(1.0, 6.0);
    final ui.Image image = await boundary.toImage(
      pixelRatio: pixelRatio.toDouble(),
    );
    final double scale = image.width / logicalWidth;
    final ui.Image finalImage = includeBranding
        ? await _compositeBranding(image, scale)
        : image;
    final ByteData? byteData = await finalImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    await showShareControlsIfHidden();
    return byteData?.buffer.asUint8List();
  }

  bool _shouldShowBrandingForCard(WrappedCard card) {
    return card.type != WrappedCardType.badge &&
        card.type != WrappedCardType.badgeDebug;
  }

  Future<void> _showSharePillOverlay() async {
    if (!mounted || _sharePillOverlayEntry != null) {
      return;
    }
    final overlayState = Overlay.of(context, rootOverlay: true);
    final RenderRepaintBoundary? shareBoundary =
        _shareButtonKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (shareBoundary == null) {
      return;
    }
    final Size size = shareBoundary.size;
    final Offset topLeft = shareBoundary.localToGlobal(Offset.zero);
    try {
      final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final double pixelRatio = math.max(1.0, math.min(devicePixelRatio, 4.0));
      final ui.Image snapshot = await shareBoundary.toImage(
        pixelRatio: pixelRatio,
      );
      _sharePillOverlaySnapshot?.dispose();
      _sharePillOverlaySnapshot = snapshot;
      final OverlayEntry entry = OverlayEntry(
        builder: (BuildContext overlayContext) {
          return Positioned(
            left: topLeft.dx,
            top: topLeft.dy,
            width: size.width,
            height: size.height,
            child: IgnorePointer(
              child: RawImage(image: snapshot, fit: BoxFit.fill),
            ),
          );
        },
      );
      overlayState.insert(entry);
      _sharePillOverlayEntry = entry;
    } catch (error, stackTrace) {
      _logger.fine("Failed to create share pill overlay", error, stackTrace);
    }
  }

  void _removeSharePillOverlay() {
    _sharePillOverlayEntry?.remove();
    _sharePillOverlayEntry = null;
    _sharePillOverlaySnapshot?.dispose();
    _sharePillOverlaySnapshot = null;
  }

  Future<ui.Image> _compositeBranding(ui.Image baseImage, double scale) async {
    final ui.Image? logo = await _loadBrandingLogoImage();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Size size = Size(
      baseImage.width.toDouble(),
      baseImage.height.toDouble(),
    );

    canvas.drawImage(baseImage, Offset.zero, Paint());

    final double brandingHeight = _kShareBrandingHeight * scale;
    final Rect brandingRect = Rect.fromLTWH(
      0,
      size.height - brandingHeight,
      size.width,
      brandingHeight,
    );
    canvas.drawRect(brandingRect, Paint()..color = const Color(0x80000000));

    if (logo != null) {
      final Rect srcRect = Rect.fromLTWH(
        0,
        0,
        logo.width.toDouble(),
        logo.height.toDouble(),
      );
      final double targetLogoWidth = _kShareBrandingLogoWidth * scale;
      final double targetLogoHeight = _kShareBrandingLogoHeight * scale;
      final Offset center = brandingRect.center.translate(
        0,
        _kShareBrandingLogoVerticalNudge * scale,
      );
      final Rect destRect = Rect.fromCenter(
        center: center,
        width: targetLogoWidth,
        height: targetLogoHeight,
      );
      canvas.drawImageRect(logo, srcRect, destRect, Paint());
    }

    final ui.Image composedImage = await recorder.endRecording().toImage(
      baseImage.width,
      baseImage.height,
    );
    return composedImage;
  }

  Future<ui.Image?> _loadBrandingLogoImage() async {
    if (_shareBrandingLogo != null) {
      return _shareBrandingLogo;
    }
    try {
      final ByteData data = await rootBundle.load("assets/ente_io_green.png");
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      _shareBrandingLogo = frame.image;
      return _shareBrandingLogo;
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to load branding logo for share export",
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<void> _initBackgroundMusic() async {
    if (_musicInitializationFuture != null) {
      _logger.fine("Music init already in progress, reusing existing future");
      return _musicInitializationFuture!;
    }
    _logger.info("Starting music initialization");
    final Future<void> initFuture = _performBackgroundMusicInit();
    _musicInitializationFuture = initFuture;
    try {
      await initFuture;
    } catch (error, stackTrace) {
      _logger.severe(
        "Unhandled error during music initialization wrapper",
        error,
        stackTrace,
      );
      _musicLoadFailed = true;
      if (mounted) {
        setState(() {
          _isMusicReady = false;
        });
      } else {
        _isMusicReady = false;
      }
    } finally {
      if (identical(_musicInitializationFuture, initFuture)) {
        _logger.fine("Music initialization future completed");
        _musicInitializationFuture = null;
      }
    }
  }

  Future<void> _performBackgroundMusicInit() async {
    _musicLoadFailed = false;
    try {
      _logger.fine("Configuring audio session for music");
      await _ensureAudioSessionConfigured();
      const String assetPath = "assets/ente_rewind_2025_music.mp3";
      _logger.fine("Setting music asset: $assetPath");
      await _audioPlayer.setAsset(assetPath, preload: true);
      _logger.fine("Music asset loaded, configuring player");
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.setShuffleModeEnabled(false);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.seek(Duration.zero);
      _logger.fine("Music player primed; marking ready");
      if (!mounted) {
        return;
      }
      setState(() {
        _isMusicReady = true;
      });
      _logger.info("Music ready; attempting initial resume");
      await _resumeMusic();
    } catch (error, stackTrace) {
      _musicLoadFailed = true;
      _logger.warning(
        "Failed to initialize Ente Rewind music",
        error,
        stackTrace,
      );
      _updateMusicPlaying(false);
      if (mounted) {
        setState(() {
          _isMusicReady = false;
        });
      } else {
        _isMusicReady = false;
      }
    }
  }

  void _handlePlayerState(PlayerState state) {
    _logger.finer(
      "Player state update: processing=${state.processingState} "
      "playing=${state.playing} ready=$_isMusicReady failed=$_musicLoadFailed "
      "muted=$_isMusicMuted closing=$_isClosing cards=${_cards.length}",
    );
    if (_musicLoadFailed || !_isMusicReady) {
      return;
    }
    if (state.processingState == ProcessingState.completed) {
      if (_isMusicMuted || _isClosing || _cards.isEmpty) {
        _updateMusicPlaying(false);
        return;
      }
      if (_audioPlayer.loopMode != LoopMode.off && state.playing) {
        _updateMusicPlaying(true);
        return;
      }
      unawaited(() async {
        try {
          await _audioPlayer.seek(Duration.zero);
          await _audioPlayer.play();
          _updateMusicPlaying(true);
        } catch (error, stackTrace) {
          _logger.warning(
            "Failed to restart Ente Rewind music",
            error,
            stackTrace,
          );
          _updateMusicPlaying(false);
        }
      }());
      return;
    }
    _updateMusicPlaying(state.playing);
  }

  Future<void> _pauseMusic() async {
    _logger.fine(
      "Pausing music (ready=$_isMusicReady playing=${_audioPlayer.playing})",
    );
    if (!_isMusicReady) {
      _updateMusicPlaying(false);
      return;
    }
    try {
      if (_audioPlayer.playing) {
        await _audioPlayer.pause();
      }
    } catch (error, stackTrace) {
      _logger.fine("Failed to pause Ente Rewind music", error, stackTrace);
    } finally {
      _updateMusicPlaying(false);
    }
  }

  Future<void> _resumeMusic() async {
    _logger.fine(
      "Resuming music (ready=$_isMusicReady muted=$_isMusicMuted "
      "cards=${_cards.length})",
    );
    if (!_isMusicReady || _isMusicMuted || _cards.isEmpty) {
      _updateMusicPlaying(false);
      return;
    }
    try {
      _logger.finer("Calling audioPlayer.play()");
      final Future<void> playFuture = _audioPlayer.play();
      unawaited(
        playFuture.catchError((Object error, StackTrace stackTrace) {
          _logger.warning(
            "Failed to play Ente Rewind music",
            error,
            stackTrace,
          );
          _updateMusicPlaying(false);
        }),
      );
      _updateMusicPlaying(true);
    } catch (error, stackTrace) {
      _logger.warning("Failed to play Ente Rewind music", error, stackTrace);
      _updateMusicPlaying(false);
    }
  }

  void _syncMusicPlayback() {
    _logger.finer(
      "Sync music playback (ready=$_isMusicReady muted=$_isMusicMuted "
      "cards=${_cards.length})",
    );
    if (!_isMusicReady || _isMusicMuted || _cards.isEmpty) {
      unawaited(_pauseMusic());
      return;
    }
    unawaited(_resumeMusic());
  }

  Future<void> _fadeOutAndStopMusic() async {
    _logger.fine(
      "Fading out and stopping music (ready=$_isMusicReady "
      "failed=$_musicLoadFailed playing=${_audioPlayer.playing})",
    );
    if (_musicLoadFailed || !_isMusicReady) {
      await _pauseMusic();
      return;
    }
    if (_isFadingOutMusic) {
      return;
    }
    _isFadingOutMusic = true;
    final double initialVolume = math.min(
      1.0,
      math.max(0.0, _audioPlayer.volume),
    );
    try {
      if (!_audioPlayer.playing) {
        await _pauseMusic();
        return;
      }
      const Duration totalDuration = Duration(milliseconds: 400);
      const int steps = 8;
      final int stepMillis = math.max(
        10,
        (totalDuration.inMilliseconds / steps).round(),
      );
      final Duration stepDuration = Duration(milliseconds: stepMillis);
      for (int i = 0; i < steps; i++) {
        final double factor = 1 - ((i + 1) / steps);
        await _audioPlayer.setVolume(initialVolume * factor);
        await Future<void>.delayed(stepDuration);
      }
      await _pauseMusic();
    } catch (error, stackTrace) {
      _logger.fine("Failed to fade out Ente Rewind music", error, stackTrace);
      await _pauseMusic();
    } finally {
      try {
        await _audioPlayer.setVolume(initialVolume);
      } catch (error, stackTrace) {
        _logger.fine(
          "Failed to restore Ente Rewind music volume",
          error,
          stackTrace,
        );
      }
      _isFadingOutMusic = false;
    }
  }

  Future<void> _handleMusicToggle() async {
    _logger.fine(
      "Music toggle pressed (ready=$_isMusicReady failed=$_musicLoadFailed "
      "muted=$_isMusicMuted playing=$_isMusicPlaying)",
    );
    if (_musicLoadFailed) {
      final bool retrySucceeded = await _retryMusicInitialization();
      if (!retrySucceeded && mounted) {
        showShortToast(context, "Music unavailable");
      }
      return;
    }
    if (!_isMusicReady) {
      showShortToast(context, "Music loading…");
      return;
    }
    if (_isMusicMuted) {
      setState(() {
        _isMusicMuted = false;
      });
      await _resumeMusic();
    } else {
      setState(() {
        _isMusicMuted = true;
      });
      await _pauseMusic();
    }
  }

  Future<bool> _retryMusicInitialization() async {
    _logger.info("Retrying music initialization");
    if (mounted) {
      setState(() {
        _isMusicMuted = false;
      });
    } else {
      _isMusicMuted = false;
    }
    await _initBackgroundMusic();
    _logger.info(
      "Music retry result: ready=$_isMusicReady failed=$_musicLoadFailed",
    );
    return !_musicLoadFailed && _isMusicReady;
  }

  void _updateMusicPlaying(bool value) {
    _logger.finer(
      "Update music playing from $_isMusicPlaying to $value "
      "(ready=$_isMusicReady muted=$_isMusicMuted failed=$_musicLoadFailed)",
    );
    if (_isMusicPlaying == value) {
      return;
    }
    if (mounted) {
      setState(() {
        _isMusicPlaying = value;
      });
    } else {
      _isMusicPlaying = value;
    }
  }

  Future<void> _ensureAudioSessionConfigured() async {
    if (_audioSessionConfigured) {
      _logger.fine("Audio session already configured; skipping");
      return;
    }
    try {
      _logger.fine("Configuring audio session via audio_session");
      final AudioSession session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _audioSessionConfigured = true;
      _logger.info("Audio session configured for music");
    } catch (error, stackTrace) {
      _logger.fine(
        "Failed to configure audio session for Ente Rewind music",
        error,
        stackTrace,
      );
    }
  }
}

class _MediaPreviewController extends InheritedWidget {
  const _MediaPreviewController({
    required super.child,
    required this.onPreviewStart,
    required this.onPreviewTapDown,
    required this.onPreviewTapCancel,
  });

  final void Function(MediaRef ref) onPreviewStart;
  final VoidCallback onPreviewTapDown;
  final VoidCallback onPreviewTapCancel;

  static _MediaPreviewController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_MediaPreviewController>();
  }

  @override
  bool updateShouldNotify(covariant _MediaPreviewController oldWidget) {
    return oldWidget.onPreviewStart != onPreviewStart ||
        oldWidget.onPreviewTapDown != onPreviewTapDown ||
        oldWidget.onPreviewTapCancel != onPreviewTapCancel;
  }
}

class _MediaPreviewOverlay extends StatelessWidget {
  const _MediaPreviewOverlay({
    required this.file,
    required this.isLoading,
    required this.onDismiss,
  });

  final EnteFile? file;
  final bool isLoading;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final Color backdropColor = Colors.black.withValues(alpha: 0.45);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: Container(color: backdropColor),
          ),
        ),
        Center(child: _buildContent(context)),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (file != null) {
      return _buildZoomableContent(context, file!);
    }
    if (isLoading) {
      final EnteColorScheme colorScheme = getEnteColorScheme(context);
      return SizedBox(
        width: 70,
        height: 70,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: colorScheme.primary400,
        ),
      );
    }
    final EnteTextTheme textTheme = getEnteTextTheme(context);
    final EnteColorScheme colorScheme = getEnteColorScheme(context);
    final String message = file == null
        ? "Preparing preview…"
        : "Full preview isn't available for this media yet";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.fillFaint.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        message,
        style: textTheme.smallMuted,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildZoomableContent(BuildContext context, EnteFile file) {
    final Size size = MediaQuery.sizeOf(context);
    final double maxWidth = size.width * 0.88;
    final double maxHeight = size.height * 0.88;
    return SizedBox(
      width: maxWidth,
      height: maxHeight,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double boxWidth = constraints.maxWidth;
          final double boxHeight = constraints.maxHeight;
          final double imageAspect = file.width > 0 && file.height > 0
              ? file.width / file.height
              : 3 / 4;
          double width = boxWidth;
          double height = width / imageAspect;
          if (height > boxHeight) {
            height = boxHeight;
            width = height * imageAspect;
          }
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                clipBehavior: Clip.antiAlias,
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black),
                  child: ZoomableImage(
                    file,
                    tagPrefix: "rewind_preview_",
                    shouldCover: false,
                    isGuestView: true,
                    backgroundDecoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
