import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:collection/collection.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/effects.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";
import "package:photos/utils/face_crop_util.dart";
import "package:photos/utils/share_util.dart";

class MemoryLanePage extends StatefulWidget {
  final PersonEntity person;

  const MemoryLanePage({required this.person, super.key});

  @override
  State<MemoryLanePage> createState() => _MemoryLanePageState();
}

const LinearGradient _memoryLaneBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF03010A),
    Color(0xFF16103C),
    Color(0xFF401963),
    Color(0xFF241348),
    Color(0xFF03010A),
  ],
  stops: [0.0, 0.3, 0.52, 0.74, 1.0],
);

class _MemoryLanePageState extends State<MemoryLanePage>
    with TickerProviderStateMixin {
  static const _frameInterval = Duration(milliseconds: 800);
  static const _cardTransitionDuration = Duration(milliseconds: 520);
  static const double _frameWidthFactor = 0.82;
  static const double _frameHeightFactor = 0.78;
  static const double _controlsDesiredGapToCard = 24;
  static const double _cardGapUpdateTolerance = 0.5;
  static const double _controlsHeightUpdateTolerance = 0.5;
  static const double _controlsHeightFallback = 140;
  // Wait for this many frames (or the available total) before auto-starting playback.
  static const int _initialFrameTarget = 120;
  static const int _frameBuildConcurrency = 6;

  final Logger _logger = Logger("MemoryLanePage");
  late final AnimationController _cardTransitionController;
  double _stackProgress = 0;
  late final ValueNotifier<double> _stackProgressNotifier;
  double _animationStartProgress = 0;
  int _targetIndex = 0;
  bool _isAnimatingCard = false;

  final List<_TimelineFrame> _frames = [];

  Timer? _playTimer;
  bool _isPlaying = false;
  bool _loggedPlaybackStart = false;
  bool _hasStartedPlayback = false;
  bool _allFramesLoaded = false;
  bool _timelineUnavailable = false;
  bool _hasMarkedTimelineSeen = false;
  int _expectedFrameCount = 0;

  int _currentIndex = 0;
  double _cardGap = 0;
  double _controlsHeight = 0;
  final GlobalKey _controlsKey = GlobalKey();
  bool _isScrubbing = false;
  double _sliderValue = 0;
  int _previousCaptionValue = 0;
  int _currentCaptionValue = 0;
  _CaptionType _currentCaptionType = _CaptionType.yearsAgo;
  int _maxCaptionDigits = 1;
  bool get _featureEnabled => flagService.facesTimeline;
  bool get _showShareAction =>
      _featureEnabled &&
      flagService.enableMemoryShareLink &&
      !isLocalGalleryMode;

  @override
  void initState() {
    super.initState();
    _cardTransitionController =
        AnimationController(vsync: this, duration: _cardTransitionDuration)
          ..addListener(_onCardAnimationTick)
          ..addStatusListener(_onCardAnimationStatusChanged);
    _stackProgressNotifier = ValueNotifier<double>(_stackProgress);
    if (_featureEnabled) {
      unawaited(_loadFrames());
    } else {
      _timelineUnavailable = true;
    }
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _cardTransitionController
      ..removeListener(_onCardAnimationTick)
      ..removeStatusListener(_onCardAnimationStatusChanged)
      ..dispose();
    _stackProgressNotifier.dispose();
    super.dispose();
  }

  void _updateStackProgress(double value) {
    _stackProgress = value;
    const double epsilon = 1e-6;
    if ((_stackProgressNotifier.value - value).abs() <= epsilon) {
      return;
    }
    _stackProgressNotifier.value = value;
  }

  Future<void> _loadFrames() async {
    _hasMarkedTimelineSeen = localSettings.hasSeenMemoryLane(
      widget.person.remoteID,
    );
    _playTimer?.cancel();
    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
    try {
      final timeline = await MemoryLaneService.instance.getTimeline(
        widget.person.remoteID,
      );
      if (!mounted) {
        return;
      }
      if (timeline == null || !timeline.isReady || timeline.entries.isEmpty) {
        setState(() {
          _timelineUnavailable = true;
          _allFramesLoaded = true;
          _frames.clear();
          _hasStartedPlayback = false;
          _loggedPlaybackStart = false;
        });
        return;
      }

      final entries = timeline.entries;
      _expectedFrameCount = entries.length;
      if (_expectedFrameCount == 0) {
        setState(() {
          _timelineUnavailable = true;
          _allFramesLoaded = true;
          _frames.clear();
          _hasStartedPlayback = false;
          _loggedPlaybackStart = false;
        });
        return;
      }

      setState(() {
        _timelineUnavailable = false;
        _allFramesLoaded = false;
        _frames.clear();
        _hasStartedPlayback = false;
        _loggedPlaybackStart = false;
        _animationStartProgress = 0;
        _targetIndex = 0;
        _isAnimatingCard = false;
        _currentIndex = 0;
        _sliderValue = 0;
        _previousCaptionValue = 0;
        _currentCaptionValue = 0;
        _currentCaptionType = _CaptionType.yearsAgo;
        _maxCaptionDigits = 1;
      });
      _updateStackProgress(0);
      _cardTransitionController
        ..stop()
        ..value = 0;

      int loadedCount = 0;
      final uniqueFileIds = entries
          .map((entry) => entry.fileId)
          .toSet()
          .toList();
      final filesById = await FilesDB.instance.getFileIDToFileFromIDs(
        uniqueFileIds,
      );
      final Map<int, Future<List<Face>?>> facesFutures = {};

      await _buildFramesInParallel(
        entries: entries,
        filesById: filesById,
        facesFutures: facesFutures,
        onFrameReady: (builtFrame) {
          if (!mounted) {
            return;
          }
          loadedCount += 1;
          _handleFrameLoaded(builtFrame, loadedCount);
        },
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _allFramesLoaded = true;
      });
      _maybeMarkTimelineSeen();
    } catch (error, stackTrace) {
      _logger.severe("Faces timeline failed to load", error, stackTrace);
      if (!mounted) {
        return;
      }
      setState(() {
        _timelineUnavailable = true;
        _allFramesLoaded = true;
        _frames.clear();
        _hasStartedPlayback = false;
        _loggedPlaybackStart = false;
      });
    }
  }

  int get _initialFrameThreshold {
    if (_expectedFrameCount <= 0) {
      return 1;
    }
    return math.max(1, math.min(_initialFrameTarget, _expectedFrameCount));
  }

  void _maybeMarkTimelineSeen() {
    if (_hasMarkedTimelineSeen || !_allFramesLoaded || _frames.isEmpty) {
      return;
    }
    if (_currentIndex != _frames.length - 1) {
      return;
    }
    _hasMarkedTimelineSeen = true;
    unawaited(localSettings.markMemoryLaneSeen(widget.person.remoteID));
  }

  void _handleFrameLoaded(_TimelineFrame frame, int loadedCount) {
    final bool isFirstFrame = _frames.isEmpty;
    final int digitCount = _captionDigitCount(frame.captionValue);
    setState(() {
      _frames.add(frame);
      _maxCaptionDigits = math.max(_maxCaptionDigits, digitCount);
      if (isFirstFrame) {
        _currentIndex = 0;
        _sliderValue = 0;
        _animationStartProgress = 0;
        _targetIndex = 0;
        _isAnimatingCard = false;
        _cardTransitionController.value = 0;
        _currentCaptionValue = frame.captionValue;
        _previousCaptionValue = frame.captionValue;
        _currentCaptionType = frame.captionType;
      }
    });
    if (isFirstFrame) {
      _updateStackProgress(0);
    }
    if (!_hasStartedPlayback && loadedCount >= _initialFrameThreshold) {
      _hasStartedPlayback = true;
      _startPlayback();
      _logPlaybackStart(_expectedFrameCount);
    }
  }

  int _captionDigitCount(int value) {
    return math.max(1, value.abs().toString().length);
  }

  Future<void> _buildFramesInParallel({
    required List<MemoryLaneEntry> entries,
    required Map<int, EnteFile> filesById,
    required Map<int, Future<List<Face>?>> facesFutures,
    required void Function(_TimelineFrame builtFrame) onFrameReady,
  }) async {
    final readyFrames = <int, _TimelineFrame?>{};
    final completer = Completer<void>();
    int nextEmitIndex = 0;
    int inFlight = 0;
    int started = 0;

    void maybeComplete() {
      if (!completer.isCompleted &&
          nextEmitIndex >= entries.length &&
          inFlight == 0 &&
          started >= entries.length) {
        completer.complete();
      }
    }

    void emitReady() {
      while (readyFrames.containsKey(nextEmitIndex)) {
        final _TimelineFrame? built = readyFrames.remove(nextEmitIndex);
        if (built != null) {
          onFrameReady(built);
        }
        nextEmitIndex += 1;
      }
      maybeComplete();
    }

    void startNext() {
      while (inFlight < _frameBuildConcurrency && started < entries.length) {
        final int index = started;
        started += 1;
        inFlight += 1;
        final entry = entries[index];
        final facesFuture = facesFutures.putIfAbsent(
          entry.fileId,
          () => MLDataDB.instance.getFacesForGivenFileID(entry.fileId),
        );
        _buildFrame(
              entry,
              file: filesById[entry.fileId],
              facesFuture: facesFuture,
            )
            .then((built) {
              readyFrames[index] = built;
            })
            .catchError((error, stackTrace) {
              readyFrames[index] = null;
            })
            .whenComplete(() {
              inFlight -= 1;
              emitReady();
              startNext();
            });
      }
      maybeComplete();
    }

    startNext();
    return completer.future;
  }

  Future<_TimelineFrame> _buildFrame(
    MemoryLaneEntry entry, {
    EnteFile? file,
    Future<List<Face>?>? facesFuture,
  }) async {
    EnteFile? effectiveFile = file;
    effectiveFile ??= await FilesDB.instance.getAnyUploadedFile(entry.fileId);
    MemoryImage? image;
    double? cropAspectRatio;
    Uint8List? bytes;
    if (effectiveFile != null) {
      final List<Face>? faces;
      if (facesFuture != null) {
        faces = await facesFuture;
      } else {
        faces = await MLDataDB.instance.getFacesForGivenFileID(entry.fileId);
      }
      final Face? face = faces?.firstWhereOrNull(
        (element) => element.faceID == entry.faceId,
      );
      if (face != null) {
        final paddedFaceCropBox = computePaddedFaceCropBox(face.detection.box);
        final int detectedImageWidth = face.fileInfo?.imageWidth ?? 0;
        final int detectedImageHeight = face.fileInfo?.imageHeight ?? 0;
        final int imageWidth = detectedImageWidth > 0
            ? detectedImageWidth
            : effectiveFile.width;
        final int imageHeight = detectedImageHeight > 0
            ? detectedImageHeight
            : effectiveFile.height;
        if (paddedFaceCropBox.width > 0 && paddedFaceCropBox.height > 0) {
          if (imageWidth > 0 && imageHeight > 0) {
            cropAspectRatio =
                (paddedFaceCropBox.width * imageWidth) /
                (paddedFaceCropBox.height * imageHeight);
          } else {
            cropAspectRatio =
                paddedFaceCropBox.width / paddedFaceCropBox.height;
          }
        }
        try {
          final cropMap = await getCachedFaceCrops(
            effectiveFile,
            [face],
            useFullFile: true,
            useTempCache: false,
          );
          bytes = cropMap?[face.faceID];
          if (bytes != null && bytes.isNotEmpty) {
            image = MemoryImage(bytes);
          }
        } catch (error, stackTrace) {
          _logger.warning(
            "Failed to fetch face crop for ${entry.faceId}",
            error,
            stackTrace,
          );
        }
      }
    }
    final creationDate = DateTime.fromMicrosecondsSinceEpoch(
      entry.creationTimeMicros,
    );
    final captionType = widget.person.data.birthDate != null
        ? _CaptionType.age
        : _CaptionType.yearsAgo;
    int captionValue;
    if (captionType == _CaptionType.age) {
      final birthDateString = widget.person.data.birthDate!;
      final birthDate = DateTime.tryParse(birthDateString);
      if (birthDate == null) {
        captionValue = MemoryLaneService.completedYearsBetween(
          creationDate,
          DateTime.now(),
        );
      } else {
        captionValue = MemoryLaneService.completedYearsBetween(
          birthDate,
          creationDate,
        );
      }
    } else {
      captionValue = MemoryLaneService.completedYearsBetween(
        creationDate,
        DateTime.now(),
      );
    }
    final timelineFrame = _TimelineFrame(
      entry: entry,
      image: image,
      creationDate: creationDate,
      captionType: captionType,
      captionValue: captionValue,
      cropAspectRatio: cropAspectRatio,
    );
    return timelineFrame;
  }

  void _scheduleCardGapUpdate(double candidateGap) {
    if ((_cardGap - candidateGap).abs() <= _cardGapUpdateTolerance) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if ((_cardGap - candidateGap).abs() <= _cardGapUpdateTolerance) {
        return;
      }
      setState(() {
        _cardGap = candidateGap;
      });
    });
  }

  void _scheduleControlsHeightUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final context = _controlsKey.currentContext;
      if (context == null) {
        return;
      }
      final Size? size = context.size;
      if (size == null) {
        return;
      }
      final double height = size.height;
      if ((_controlsHeight - height).abs() <= _controlsHeightUpdateTolerance) {
        return;
      }
      setState(() {
        _controlsHeight = height;
      });
    });
  }

  void _logPlaybackStart(int frameCount) {
    if (_loggedPlaybackStart) return;
    _logger.info(
      "playback_start person=${widget.person.remoteID} frames=$frameCount",
    );
    _loggedPlaybackStart = true;
  }

  void _startPlayback() {
    _playTimer?.cancel();
    if (_frames.isEmpty) return;
    _playTimer = Timer.periodic(_frameInterval, (_) {
      if (!mounted || !_isPlaying || _frames.isEmpty) return;
      _showNextFrame();
    });
    setState(() {
      _isPlaying = true;
    });
  }

  void _pausePlayback() {
    _playTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _showNextFrame() {
    if (_frames.isEmpty || _isAnimatingCard) return;
    if (_currentIndex >= _frames.length - 1) {
      _pausePlayback();
      return;
    }
    final nextIndex = _currentIndex + 1;
    _setCurrentFrame(nextIndex);
  }

  void _setCurrentFrame(int index) {
    _animateToIndex(index);
  }

  void _jumpToIndex(int index) {
    if (_frames.isEmpty) {
      return;
    }
    final clamped = index.clamp(0, _frames.length - 1);
    _cardTransitionController.stop();
    _updateStackProgress(clamped.toDouble());
    setState(() {
      _isAnimatingCard = false;
      _animationStartProgress = clamped.toDouble();
      _targetIndex = clamped;
      _currentIndex = clamped;
      final frame = _frames[clamped];
      _previousCaptionValue = _currentCaptionValue;
      _currentCaptionValue = frame.captionValue;
      _currentCaptionType = frame.captionType;
      _sliderValue = clamped.toDouble();
    });
    _maybeMarkTimelineSeen();
  }

  void _animateToIndex(int index) {
    if (_frames.isEmpty) {
      return;
    }
    final clamped = index.clamp(0, _frames.length - 1);
    final targetProgress = clamped.toDouble();
    if (!_isAnimatingCard && clamped == _currentIndex) {
      setState(() {
        _sliderValue = targetProgress;
      });
      return;
    }

    if (_isAnimatingCard && _targetIndex == clamped) {
      return;
    }

    _animationStartProgress = _stackProgress;
    _targetIndex = clamped;
    _isAnimatingCard = true;
    final distance = (targetProgress - _animationStartProgress).abs();
    final multiplier = distance.clamp(1.0, 4.0);
    _cardTransitionController.duration = Duration(
      milliseconds: (_cardTransitionDuration.inMilliseconds * multiplier)
          .round(),
    );
    _cardTransitionController
      ..reset()
      ..forward();
    setState(() {
      _sliderValue = targetProgress;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_featureEnabled) {
      final l10n = context.l10n;
      final colorScheme = getEnteColorScheme(context);
      final textTheme = getEnteTextTheme(context);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.facesTimelineAppBarTitle)),
        body: Center(
          child: Text(
            l10n.facesTimelineUnavailable,
            style: textTheme.body.copyWith(color: colorScheme.textBase),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Theme(
      data: darkThemeData,
      child: Builder(
        builder: (context) {
          final l10n = context.l10n;
          final title = l10n.facesTimelineAppBarTitle;
          final colorScheme = getEnteColorScheme(context);
          final textTheme = getEnteTextTheme(context);
          final titleStyle = textTheme.h3Bold.copyWith(letterSpacing: -2);
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: _memoryLaneBackgroundGradient,
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                centerTitle: false,
                foregroundColor: colorScheme.textBase,
                automaticallyImplyLeading: false,
                titleSpacing: 24,
                title: Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showShareAction)
                          _buildAppBarActionButton(
                            context: context,
                            icon: Icons.share,
                            tooltip: l10n.shareLink,
                            onTap: () async {
                              _pausePlayback();
                              final shareLinkData =
                                  await _getOrCreateMemoryLaneLinkData(context);
                              if (!context.mounted || shareLinkData == null) {
                                return;
                              }
                              await shareText(
                                shareLinkData.$1,
                                context: context,
                              );
                            },
                          ),
                        if (_showShareAction) const SizedBox(width: 12),
                        _buildAppBarActionButton(
                          context: context,
                          icon: Icons.close,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).closeButtonTooltip,
                          onTap: () async {
                            await Navigator.of(context).maybePop();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              body: Stack(
                children: [
                  if (_timelineUnavailable && _allFramesLoaded)
                    Center(
                      child: Text(
                        l10n.facesTimelineUnavailable,
                        style: textTheme.body,
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final viewPadding = MediaQuery.of(context).viewPadding;
                        final double bottomInset = viewPadding.bottom;
                        final double bottomPadding = math.max(12, bottomInset);
                        const double topPadding = 12;
                        final double gapToTop = _cardGap + topPadding;
                        const double desiredGap = _controlsDesiredGapToCard;
                        final double overlap = math.max(
                          0,
                          gapToTop - desiredGap,
                        );
                        final double controlsHeight = _controlsHeight > 0
                            ? _controlsHeight
                            : _controlsHeightFallback;
                        final double reservedHeight =
                            topPadding + bottomPadding + controlsHeight;
                        final Widget controlsContent = KeyedSubtree(
                          key: _controlsKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCaption(context),
                              const SizedBox(height: 16),
                              _buildControls(context),
                            ],
                          ),
                        );
                        _scheduleControlsHeightUpdate();
                        return Stack(
                          children: [
                            Column(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: RepaintBoundary(
                                          child: ValueListenableBuilder<double>(
                                            valueListenable:
                                                _stackProgressNotifier,
                                            builder:
                                                (context, stackProgress, _) {
                                                  return _buildFrameView(
                                                    context,
                                                    stackProgress,
                                                  );
                                                },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: reservedHeight),
                              ],
                            ),
                            Positioned(
                              left: 24,
                              right: 24,
                              bottom: bottomPadding + overlap,
                              child: controlsContent,
                            ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFrameView(BuildContext context, double currentStackProgress) {
    final colorScheme = getEnteColorScheme(context);
    if (_frames.isEmpty) {
      return Center(
        key: const ValueKey<String>("faces_timeline_empty"),
        child: FractionallySizedBox(
          widthFactor: _frameWidthFactor,
          heightFactor: _frameHeightFactor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.backgroundElevated,
              borderRadius: BorderRadius.circular(28),
              boxShadow: (Theme.of(context).brightness == Brightness.dark)
                  ? shadowFloatDark
                  : shadowFloatLight,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ColoredBox(
                color: colorScheme.backgroundElevated2,
                child: Center(
                  child: Icon(
                    Icons.person_outline,
                    size: 72,
                    color: colorScheme.strokeMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final stackProgress = currentStackProgress.clamp(
      0.0,
      (_frames.length - 1).toDouble(),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<_CardSlice> slices = [];
    final startIndex = math.max(0, stackProgress.floor() - 3);
    final endIndex = math.min(_frames.length - 1, stackProgress.ceil() + 4);

    for (int i = startIndex; i <= endIndex; i++) {
      final distance = i - stackProgress;
      if (distance < -4.5 || distance > 5.5) {
        continue;
      }
      slices.add(_CardSlice(index: i, distance: distance));
    }

    final futureSlices = slices.where((slice) => slice.distance >= 0).toList()
      ..sort((a, b) => b.distance.compareTo(a.distance));
    final presentAndPastSlices =
        slices.where((slice) => slice.distance < 0).toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));

    return Center(
      child: FractionallySizedBox(
        widthFactor: _frameWidthFactor,
        heightFactor: _frameHeightFactor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : constraints.biggest.width;
            final cardHeight = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : constraints.biggest.height;
            if (cardHeight > 0) {
              final double parentHeight = cardHeight / _frameHeightFactor;
              final double gap = math.max(0, (parentHeight - cardHeight) / 2);
              _scheduleCardGapUpdate(gap);
            }
            final orderedSlices = <_CardSlice>[
              ...futureSlices,
              ...presentAndPastSlices,
            ];
            final children = orderedSlices.isEmpty
                ? [
                    _MemoryLaneCard(
                      key: ValueKey<int>(_currentIndex),
                      frame: _frames[_currentIndex],
                      distance: 0,
                      isDarkMode: isDark,
                      colorScheme: colorScheme,
                      cardWidth: cardWidth,
                      cardHeight: cardHeight,
                      blurEnabled: !_isScrubbing,
                    ),
                  ]
                : orderedSlices
                      .map(
                        (slice) => _MemoryLaneCard(
                          key: ValueKey<int>(slice.index),
                          frame: _frames[slice.index],
                          distance: slice.distance,
                          isDarkMode: isDark,
                          colorScheme: colorScheme,
                          cardWidth: cardWidth,
                          cardHeight: cardHeight,
                          blurEnabled: !_isScrubbing,
                        ),
                      )
                      .toList();
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: children,
            );
          },
        ),
      ),
    );
  }

  Widget _buildCaption(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final l10n = context.l10n;
    final captionType = _currentCaptionType;
    final isPlaying = _isPlaying;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final localeName = l10n.localeName;
    final numberFormat = NumberFormat.decimalPattern(localeName);
    final int currentRounded = _currentCaptionValue.clamp(0, 1000);
    final int previousRounded = _previousCaptionValue.clamp(0, 1000);
    final TextStyle baseStyle = textTheme.bodyMuted.copyWith(
      color: isDark
          ? colorScheme.textMuted
          : colorScheme.textBase.withValues(alpha: 0.72),
    );
    final TextStyle numberStyle = textTheme.body.copyWith(
      color: colorScheme.fillBase,
      fontWeight: FontWeight.w600,
    );
    final int digits = math.max(3, _maxCaptionDigits);
    final int slotSampleValue = _maxValueForDigits(digits);
    final String sampleString = numberFormat.format(slotSampleValue);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextPainter samplePainter = TextPainter(
      text: TextSpan(text: sampleString, style: numberStyle),
      textDirection: ui.TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final double slotWidth = samplePainter.width;
    final double slotHeight = samplePainter.height;
    final String formattedCurrent = numberFormat.format(currentRounded);
    String fullText;
    if (captionType == _CaptionType.age) {
      fullText = l10n.facesTimelineCaptionYearsOld(
        name: widget.person.data.name,
        count: currentRounded,
      );
    } else {
      fullText = l10n.facesTimelineCaptionYearsAgo(count: currentRounded);
      if (fullText.contains("#")) {
        fullText = fullText.replaceAll("#", formattedCurrent);
      }
      final String name = widget.person.data.name;
      if (name.isNotEmpty) {
        fullText = "$name $fullText";
      }
    }
    final int insertionIndex = fullText.indexOf(formattedCurrent);
    final InlineSpan captionSpan;
    if (insertionIndex == -1) {
      captionSpan = TextSpan(text: fullText, style: baseStyle);
    } else {
      final String prefix = fullText.substring(0, insertionIndex);
      final String suffix = fullText.substring(
        insertionIndex + formattedCurrent.length,
      );
      captionSpan = TextSpan(
        children: [
          TextSpan(text: prefix, style: baseStyle),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: SizedBox(
              width: slotWidth,
              height: slotHeight,
              child: Center(
                child: _RollingCounter(
                  value: currentRounded,
                  previousValue: previousRounded,
                  textStyle: numberStyle,
                  numberFormat: numberFormat,
                ),
              ),
            ),
          ),
          TextSpan(text: suffix, style: baseStyle),
        ],
      );
    }
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: isPlaying
                ? l10n.facesTimelinePlaybackPause
                : l10n.facesTimelinePlaybackPlay,
            child: IconButton(
              onPressed: _frames.isEmpty ? null : _togglePlayback,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.fillFaint,
                foregroundColor: isDark
                    ? colorScheme.textMuted
                    : colorScheme.textBase.withValues(alpha: 0.72),
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.all(8),
                shape: const CircleBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: RichText(textAlign: TextAlign.center, text: captionSpan),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final frameCount = _frames.length;
    final bool hasMultipleFrames = frameCount > 1;
    final double maxValue = hasMultipleFrames
        ? (frameCount - 1).toDouble()
        : 0.0;
    final double sliderValue = hasMultipleFrames
        ? _sliderValue.clamp(0.0, maxValue)
        : 0.0;
    const Color activeTrackColor = Colors.white;
    final Color inactiveTrackColor =
        (isDark ? colorScheme.fillBaseGrey : colorScheme.strokeMuted)
            .withValues(alpha: isDark ? 0.55 : 0.48);
    final bool sliderDiscrete = _allFramesLoaded && _expectedFrameCount > 1;
    final int? divisions = sliderDiscrete
        ? (_expectedFrameCount - 1) * 4
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: activeTrackColor,
            inactiveTrackColor: inactiveTrackColor,
            tickMarkShape: SliderTickMarkShape.noTickMark,
            thumbColor: Colors.white,
            overlayColor: Colors.transparent,
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const _MemoryLaneSliderThumbShape(),
          ),
          child: Slider(
            value: sliderValue.toDouble(),
            min: 0.0,
            max: frameCount > 1 ? maxValue : 0.0,
            divisions: divisions,
            onChangeStart: frameCount > 1
                ? (value) {
                    _pausePlayback();
                    _isAnimatingCard = false;
                    _cardTransitionController.stop();
                    setState(() {
                      _isScrubbing = true;
                    });
                  }
                : null,
            onChanged: frameCount > 1
                ? (value) {
                    final clamped = value.clamp(0.0, maxValue);
                    _updateStackProgress(clamped);
                    setState(() {
                      _sliderValue = clamped;
                      _currentIndex = clamped.round().clamp(0, frameCount - 1);
                      final frame = _frames[_currentIndex];
                      _previousCaptionValue = _currentCaptionValue;
                      _currentCaptionValue = frame.captionValue;
                      _currentCaptionType = frame.captionType;
                      _isScrubbing = true;
                    });
                    _maybeMarkTimelineSeen();
                  }
                : null,
            onChangeEnd: frameCount > 1
                ? (value) {
                    final target = value
                        .round()
                        .clamp(0, frameCount - 1)
                        .toInt();
                    final double targetProgress = target.toDouble();
                    setState(() {
                      _currentIndex = target;
                      _sliderValue = targetProgress;
                      _isScrubbing = false;
                    });
                    _updateStackProgress(targetProgress);
                    _maybeMarkTimelineSeen();
                  }
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildAppBarActionButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required Future<void> Function() onTap,
  }) {
    final colorScheme = getEnteColorScheme(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () async {
          await onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.fillFaint,
          ),
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: colorScheme.textBase),
        ),
      ),
    );
  }

  Future<(String, int)?> _getOrCreateMemoryLaneLinkData(
    BuildContext context,
  ) async {
    final l10n = context.l10n;
    final dialog = createProgressDialog(context, l10n.creatingLink);
    await dialog.show();
    try {
      final timeline = await MemoryLaneService.instance.getTimeline(
        widget.person.remoteID,
      );
      if (timeline == null || !timeline.isReady || timeline.entries.isEmpty) {
        await dialog.hide();
        if (context.mounted) {
          showShortToast(context, l10n.somethingWentWrong);
        }
        return null;
      }
      final shareLinkData = await MemoryShareService.instance
          .getOrCreateMemoryLaneLink(
            entries: timeline.entries,
            title: l10n.facesTimelineAppBarTitle,
            personId: widget.person.remoteID,
            personName: widget.person.data.name,
            birthDate: widget.person.data.birthDate,
          );
      await dialog.hide();
      return shareLinkData;
    } catch (e) {
      await dialog.hide();
      if (context.mounted) {
        await showGenericErrorBottomSheet(context: context, error: e);
      }
      return null;
    }
  }

  void _togglePlayback() {
    if (_frames.isEmpty) {
      return;
    }
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _resumeAutoPlay();
    }
  }

  void _resumeAutoPlay() {
    if (_frames.isEmpty) {
      return;
    }
    final bool atEnd = _currentIndex >= _frames.length - 1;
    if (atEnd) {
      _jumpToIndex(0);
    }
    _startPlayback();
  }

  void _onCardAnimationTick() {
    if (!_cardTransitionController.isAnimating && !_isAnimatingCard) {
      return;
    }
    final eased = Curves.easeInOutCubic.transform(
      _cardTransitionController.value,
    );
    final progress = ui.lerpDouble(
      _animationStartProgress,
      _targetIndex.toDouble(),
      eased,
    );
    if (progress == null) {
      return;
    }
    _updateStackProgress(progress);
  }

  void _onCardAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    if (_frames.isEmpty) {
      setState(() {
        _isAnimatingCard = false;
      });
      _updateStackProgress(0);
      return;
    }
    final clampedIndex = _targetIndex.clamp(0, _frames.length - 1);
    setState(() {
      _isAnimatingCard = false;
      _currentIndex = clampedIndex;
      final frame = _frames[clampedIndex];
      _previousCaptionValue = _currentCaptionValue;
      _currentCaptionValue = frame.captionValue;
      _currentCaptionType = frame.captionType;
      _sliderValue = clampedIndex.toDouble();
    });
    _updateStackProgress(clampedIndex.toDouble());
    _maybeMarkTimelineSeen();
  }
}

class _TimelineFrame {
  final MemoryLaneEntry entry;
  final MemoryImage? image;
  final DateTime creationDate;
  final _CaptionType captionType;
  final int captionValue;
  final double? cropAspectRatio;
  final Map<int?, ImageProvider<Object>> _resizedImageCache = {};

  _TimelineFrame({
    required this.entry,
    required this.image,
    required this.creationDate,
    required this.captionType,
    required this.captionValue,
    required this.cropAspectRatio,
  });

  ImageProvider<Object>? resizedImage({int? cacheWidth}) {
    final baseImage = image;
    if (baseImage == null) {
      return null;
    }
    return _resizedImageCache.putIfAbsent(cacheWidth, () {
      // Decode face crops with width only so BoxFit.cover can crop them
      // naturally without forcing the crop to the card's aspect ratio.
      return ResizeImage.resizeIfNeeded(cacheWidth, null, baseImage);
    });
  }
}

class _CardSlice {
  final int index;
  final double distance;

  const _CardSlice({required this.index, required this.distance});
}

class _MemoryLaneCard extends StatelessWidget {
  static const double _cardRadius = 28;
  // Keep in sync with the maximum value returned by [_calculateScale].
  static const double _maxCardScale = 1.02;
  static const double _cacheDecodeSafetyMargin = 1.15;

  final _TimelineFrame frame;
  final double distance;
  final bool isDarkMode;
  final EnteColorScheme colorScheme;
  final double cardWidth;
  final double cardHeight;
  final bool blurEnabled;

  const _MemoryLaneCard({
    required this.frame,
    required this.distance,
    required this.isDarkMode,
    required this.colorScheme,
    required this.cardWidth,
    required this.cardHeight,
    required this.blurEnabled,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scale = _calculateScale(distance);
    final yOffset = _calculateYOffset(distance);
    final opacity = _calculateOpacity(distance);
    // Skip the expensive ImageFiltered blur for distant cards where the
    // combination of low opacity and dark overlay already obscures detail.
    final blurSigma = blurEnabled && distance < 3.0
        ? _calculateBlur(distance)
        : 0.0;
    final rotation = _calculateRotation(distance);
    final overlayOpacity = _calculateOverlayOpacity(distance);
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int? imageCacheWidth = _cacheDimensionFor(
      _coveringDecodeWidth(frame.cropAspectRatio),
      dpr,
    );

    final cardShadow = _shadowForCard(distance);
    // Emphasize the active card by delaying the date reveal until the card is
    // nearly centered; keeps background cards calm while the primary one lifts.
    final double emphasisDistance = distance.abs();
    final double activation = (1 - (emphasisDistance * 1.8)).clamp(
      0.0,
      1.0,
    ); // hide until near front
    final double emphasis = Curves.easeOutQuad.transform(activation);
    final double dateOpacity = emphasis;
    final double gradientAlpha = 0.6 * emphasis;
    final double textShadowAlpha = 0.5 * emphasis;
    final double dateYOffset = ui.lerpDouble(28, 0, emphasis) ?? 0;
    final double dateScale = ui.lerpDouble(0.94, 1, emphasis) ?? 1;
    final String localeTag = Localizations.localeOf(context).toLanguageTag();
    final String formattedDate = DateFormat(
      "d MMM yyyy",
      localeTag,
    ).format(frame.creationDate.toLocal());
    final textTheme = getEnteTextTheme(context);

    final cardContent = ClipRRect(
      borderRadius: BorderRadius.circular(_cardRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(blurSigma, imageCacheWidth),
          if (overlayOpacity > 0)
            Container(
              color: colorScheme.backgroundColour.withValues(
                alpha: overlayOpacity,
              ),
            ),
          if (frame.image == null)
            Center(
              child: Icon(
                Icons.person_outline,
                size: 72,
                color: colorScheme.strokeMuted,
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: dateOpacity,
              child: Transform.translate(
                offset: Offset(0, dateYOffset),
                child: Transform.scale(
                  scale: dateScale,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colorScheme.backgroundColour.withValues(
                            alpha: gradientAlpha,
                          ),
                          colorScheme.backgroundColour.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
                    child: Text(
                      formattedDate,
                      textAlign: TextAlign.center,
                      style: textTheme.smallMuted.copyWith(
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(
                              alpha: textShadowAlpha,
                            ),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final transform = Matrix4.identity()
      ..translateByDouble(0.0, yOffset, 0.0, 1.0)
      ..rotateZ(rotation)
      ..scaleByDouble(scale, scale, 1.0, 1.0);

    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_cardRadius),
                boxShadow: cardShadow,
              ),
              child: cardContent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(double blurSigma, int? cacheWidth) {
    final resizedImage = frame.resizedImage(cacheWidth: cacheWidth);
    final Widget base = resizedImage != null
        ? Image(
            image: resizedImage,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
          )
        : ColoredBox(color: colorScheme.backgroundElevated2);
    if (blurSigma <= 0) {
      return base;
    }
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: base,
    );
  }

  double _coveringDecodeWidth(double? imageAspectRatio) {
    if (imageAspectRatio == null ||
        !imageAspectRatio.isFinite ||
        imageAspectRatio <= 0) {
      return cardWidth;
    }
    // BoxFit.cover needs enough decoded height for tall portrait cards.
    return math.max(cardWidth, cardHeight * imageAspectRatio);
  }

  static int? _cacheDimensionFor(double logicalDimension, double dpr) {
    if (!logicalDimension.isFinite ||
        logicalDimension <= 0 ||
        !dpr.isFinite ||
        dpr <= 0) {
      return null;
    }
    final int rawCacheDimension =
        (logicalDimension * dpr * _maxCardScale * _cacheDecodeSafetyMargin)
            .ceil();
    return rawCacheDimension > 0 ? rawCacheDimension : null;
  }

  List<BoxShadow> _shadowForCard(double distance) {
    final double baseOpacity = isDarkMode ? 0.55 : 0.3;
    if (distance > 0) {
      return [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: math.max(0.0, baseOpacity - distance * 0.12),
          ),
          blurRadius: 38,
          offset: const Offset(0, 26),
          spreadRadius: -6,
        ),
      ];
    }
    final dampening = math.max(0.2, 1 - distance.abs() * 0.25);
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: baseOpacity * dampening),
        blurRadius: 34,
        offset: const Offset(0, 24),
        spreadRadius: -12,
      ),
    ];
  }

  double _calculateScale(double distance) {
    if (distance >= 0) {
      return math.max(0.84, 1.0 - distance * 0.05);
    }
    final falling = 1.0 - distance.abs() * 0.02;
    return falling.clamp(0.82, 1.02);
  }

  double _calculateYOffset(double distance) {
    if (distance >= 0) {
      final compression = math.pow(0.72, distance).toDouble();
      return -cardHeight * 0.14 * distance * compression;
    }
    final downward = distance.abs();
    final easedComponent = math.pow(downward, 1.45).toDouble();
    final travel = downward * (2.8 + 1.8 * downward);
    return cardHeight * (travel + easedComponent * 0.65);
  }

  double _calculateBlur(double distance) {
    if (distance <= 0) {
      return 0;
    }
    // Drop blur aggressively once the card is mostly in view so the hero frame
    // looks sharp as soon as it settles.
    const double clearDistance = 0.15;
    const double blurMultiplier = 10;
    final double effective = math.max(0, distance - clearDistance);
    return math.min(20, (effective + 0.05) * blurMultiplier);
  }

  double _calculateRotation(double distance) {
    if (distance <= 0) {
      return 0;
    }
    final clamped = distance.clamp(0.0, 3.0);
    const double base = 0.035; // ~2 degrees
    final falloff = math.max(0.2, 1 - clamped * 0.18);
    return base * clamped * falloff;
  }

  double _calculateOpacity(double distance) {
    if (distance >= 0) {
      return math.max(0.35, 1 - distance * 0.22);
    }
    final drop = distance.abs();
    const fadeStart = 0.9;
    if (drop <= fadeStart) {
      return 1.0;
    }
    const double fadeRange = 0.55;
    final t = ((drop - fadeStart) / fadeRange).clamp(0.0, 1.0);
    return math.max(0.0, 1.0 - t);
  }

  double _calculateOverlayOpacity(double distance) {
    if (distance <= 0) {
      return 0;
    }
    const double overlayMax = 0.45;
    const double reachDistance = 3.0;
    final double normalized = (distance / reachDistance).clamp(0.0, 1.0);
    final double eased = Curves.easeOutCubic.transform(normalized);
    // Fade the lift overlay much earlier so the card looks settled sooner.
    return overlayMax * eased;
  }
}

enum _CaptionType { age, yearsAgo }

class _MemoryLaneSliderThumbShape extends SliderComponentShape {
  const _MemoryLaneSliderThumbShape();

  static const double _thumbRadius = 12;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required ui.TextDirection textDirection,
    required double textScaleFactor,
    required double value,
    required Size sizeWithOverflow,
  }) {
    final Color color =
        sliderTheme.thumbColor ?? sliderTheme.activeTrackColor ?? Colors.white;
    final canvas = context.canvas;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);
    canvas.drawCircle(center.translate(0, 1), _thumbRadius, shadowPaint);
    final paint = Paint()..color = color;
    canvas.drawCircle(center, _thumbRadius, paint);
  }
}

class _RollingCounter extends StatelessWidget {
  const _RollingCounter({
    required this.value,
    required this.previousValue,
    required this.textStyle,
    required this.numberFormat,
  });

  final int value;
  final int previousValue;
  final TextStyle textStyle;
  final NumberFormat numberFormat;

  @override
  Widget build(BuildContext context) {
    final ValueKey<int> currentKey = ValueKey<int>(value);
    final double direction = value >= previousValue ? 1.0 : -1.0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final bool isCurrent = child.key == currentKey;
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: isCurrent ? Curves.easeOutCubic : Curves.easeInCubic,
        );
        return AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, child) {
            if (child == null) {
              return const SizedBox.shrink();
            }
            final double progress = isCurrent ? curved.value : 1 - curved.value;
            final double offsetY = isCurrent
                ? direction * (1 - progress)
                : -direction * progress;
            return ClipRect(
              child: FractionalTranslation(
                translation: Offset(0, offsetY),
                child: child,
              ),
            );
          },
        );
      },
      child: Align(
        key: currentKey,
        alignment: Alignment.center,
        child: Text(numberFormat.format(value), style: textStyle),
      ),
    );
  }
}

int _maxValueForDigits(int digits) {
  if (digits <= 0) {
    return 0;
  }
  int value = 0;
  for (int i = 0; i < digits; i++) {
    value = (value * 10) + 9;
  }
  return value;
}
