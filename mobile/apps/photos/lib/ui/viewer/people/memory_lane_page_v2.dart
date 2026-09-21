import "dart:async";
import "dart:math" as math;
import "dart:typed_data";
import "dart:ui";

import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart" show SystemUiOverlayStyle;
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart" show DateFormat, NumberFormat;
import "package:logging/logging.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memory_lane/memory_lane_cache_service.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/viewer/gallery/jump_to_date_gallery.dart";
import "package:photos/ui/viewer/people/memory_lane_page.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";
import "package:photos/utils/share_util.dart";

Future<void> openMemoryLanePage(
  BuildContext context, {
  required String personId,
  required PersonEntity? person,
  bool isCluster = false,
}) async {
  if (!context.mounted || (!isCluster && person == null)) return;

  final Widget page;
  if (flagService.internalUser) {
    page = MemoryLanePageV2(
      personId: personId,
      isCluster: isCluster,
      person: person,
    );
  } else {
    page = MemoryLanePage(
      personId: personId,
      isCluster: isCluster,
      person: person,
    );
  }
  await routeToPage(context, page);
}

class MemoryLanePageV2 extends StatefulWidget {
  final String personId;
  final bool isCluster;
  final PersonEntity? person;
  final bool isActive;
  final VoidCallback? onNextMemory;
  final VoidCallback? onPreviousMemory;
  final bool isFromMemoriesStrip;

  const MemoryLanePageV2({
    required this.personId,
    required this.isCluster,
    required this.person,
    this.isActive = true,
    this.onNextMemory,
    this.onPreviousMemory,
    this.isFromMemoriesStrip = false,
    super.key,
  });

  @override
  State<MemoryLanePageV2> createState() => _MemoryLanePageV2State();
}

class _MemoryLanePageV2State extends State<MemoryLanePageV2> {
  late final _playbackInterval = Duration(
    seconds: widget.isFromMemoriesStrip ? 3 : 1,
  );

  final _logger = Logger("MemoryLanePageV2");
  Timer? _playbackTimer;
  AnimationController? _progressAnimationController;
  final _playbackElapsed = Stopwatch();
  Object? _playbackToken;
  int? _photoPointer;
  bool _useFastTransition = false;
  late final Future<void> _memoryLaneLoaded;
  Key _currentEntryKey = UniqueKey();
  MemoryLanePersonTimeline? _timeline;
  final List<MemoryLaneEntry> _entries = [];
  _Chunkinator<MemoryLaneEntry, Uint8List?>? _chunkinator;
  final Map<(Future<Uint8List?>, Size, bool), Future<(Uint8List, int)?>>
  _decodedEntries = {};
  final List<EnteFile> _files = [];
  int i = 0;
  bool _hasMarkedScheduleSeen = false;
  MemoryLaneSchedule? _schedule;

  @override
  void initState() {
    super.initState();
    _memoryLaneLoaded = _loadMemoryLane();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final musicController = MemoryAudioScope.maybeOf(context)?.controller;
    if (widget.isActive) {
      unawaited(musicController?.setViewerActionPaused(true));
    }
  }

  @override
  void didUpdateWidget(covariant MemoryLanePageV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (!widget.isActive) {
      _pause();
      return;
    }
    unawaited(_play(0));
    unawaited(
      MemoryAudioScope.maybeOf(
        context,
        listen: false,
      )?.controller?.setViewerActionPaused(true),
    );
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _chunkinator?.dispose();
    super.dispose();
  }

  Future<void> _loadMemoryLane() async {
    try {
      if (widget.isFromMemoriesStrip) {
        final schedule = await MemoryLaneCacheService.instance
            .getCurrentMemoriesStripSchedule();
        if (!mounted) return;
        if (schedule?.personID == widget.personId &&
            schedule?.isCluster == widget.isCluster) {
          _schedule = schedule;
        }
      }
      final timeline = await MemoryLaneService.instance.getTimeline(
        widget.personId,
        isCluster: widget.isCluster,
      );
      if (!mounted) return;
      _timeline = timeline;
      if (timeline == null ||
          !timeline.isEligible ||
          timeline.entries.isEmpty) {
        return;
      }
      final files = await MemoryLaneService.instance.getTimelineFiles(
        timeline.entries.map((entry) => entry.fileId).toSet(),
      );
      if (!mounted) return;
      for (final entry in timeline.entries) {
        final file = files[entry.fileId];
        if (file != null) {
          _files.add(file);
          _entries.add(entry);
        }
      }
      const chunkSize = 5;
      _chunkinator = _Chunkinator(
        keys: _entries,
        chunkSize: chunkSize,
        fetch: (entry) async {
          if (!mounted) return null;
          return _loadEntry(entry, files[entry.fileId]!);
        },
      );
      unawaited(_play(0));
    } catch (error) {
      if (!mounted ||
          !widget.isActive ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final navigator = Navigator.of(context);
      navigator.pop();
      await showGenericErrorDialog(context: navigator.context, error: error);
    }
  }

  Future<void> _play(int index, {bool fastTransition = false}) async {
    if (!widget.isActive || _entries.isEmpty) return;
    final token = Object();
    setState(() {
      _playbackTimer?.cancel();
      _playbackElapsed
        ..stop()
        ..reset();
      _progressAnimationController?.reset();
      _selectEntry(index, fastTransition: fastTransition);
      _playbackToken = token;
    });
    await _chunkinator!.get(_entries[index]);
    if (!mounted || !widget.isActive || _playbackToken != token) return;
    _playbackElapsed.start();
    _progressAnimationController?.forward(from: 0);
    _playbackTimer = Timer(_playbackInterval, () {
      if (index < _entries.length - 1) {
        unawaited(_play(index + 1));
      } else {
        _pause();
        widget.onNextMemory?.call();
      }
    });
  }

  void _pause() {
    setState(() {
      _playbackTimer?.cancel();
      _playbackElapsed.stop();
      _progressAnimationController?.stop();
      _playbackToken = null;
    });
  }

  void _seekFromPosition(double x, double width) {
    if (width <= 0) return;
    final index = (x / width * _entries.length).floor().clamp(
      0,
      _entries.length - 1,
    );
    setState(() {
      _playbackTimer?.cancel();
      _playbackToken = null;
      _selectEntry(index, fastTransition: true);
    });
  }

  void _onPhotoPointerEnd(PointerEvent event) {
    if (event.pointer != _photoPointer) return;
    _photoPointer = null;
    unawaited(_play(i, fastTransition: true));
  }

  Future<Uint8List?> _loadEntry(MemoryLaneEntry entry, EnteFile file) async {
    try {
      final mlDataDB = isLocalGalleryMode
          ? MLDataDB.localGalleryInstance
          : MLDataDB.instance;
      final List<Face>? faces = await mlDataDB.getFacesForGivenFileID(
        entry.fileId,
      );
      final face = faces?.firstWhereOrNull(
        (face) => face.faceID == entry.faceId,
      );
      if (face == null) return null;
      final crops = await getCachedFaceCrops(file, [face], useTempCache: false);
      final bytes = crops?[entry.faceId];
      if (bytes != null && bytes.isNotEmpty) {
        return bytes;
      }
      return null;
    } catch (e, s) {
      _logger.severe("Failed to load memory lane entry", e, s);
      return null;
    }
  }

  Future<(Uint8List, int)?> _fetchEntry(
    Future<Uint8List?> entry,
    Size targetSize, {
    bool fitWithin = false,
  }) {
    return _decodedEntries.putIfAbsent(
      (entry, targetSize, fitWithin),
      () async {
        final bytes = await entry;
        if (bytes == null || !mounted) return null;
        final buffer = await ImmutableBuffer.fromUint8List(bytes);
        try {
          final descriptor = await ImageDescriptor.encoded(buffer);
          try {
            final scale = (fitWithin ? math.min : math.max)(
              targetSize.width / descriptor.width,
              targetSize.height / descriptor.height,
            );
            final scaledWidth = descriptor.width * scale;
            final decodeWidth =
                (fitWithin ? scaledWidth.floor() : scaledWidth.ceil()).clamp(
                  1,
                  descriptor.width,
                );
            return (bytes, decodeWidth);
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
      },
    );
  }

  void _selectEntry(int index, {bool fastTransition = false}) {
    if (i != index) {
      _currentEntryKey = UniqueKey();
      _useFastTransition = fastTransition;
    }
    i = index;
    if (index != _entries.length - 1) {
      _hasMarkedScheduleSeen = false;
      return;
    }
    final entryKey = _currentEntryKey;
    unawaited(
      _chunkinator!.get(_entries[index]).then((bytes) async {
        if (bytes == null ||
            !mounted ||
            !widget.isActive ||
            _currentEntryKey != entryKey ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        final markScheduleSeen = !_hasMarkedScheduleSeen;
        _hasMarkedScheduleSeen = true;
        if (!localSettings.hasSeenMemoryLane(widget.personId)) {
          await localSettings.markMemoryLaneSeen(widget.personId);
        }
        final schedule = _schedule;
        if (markScheduleSeen && schedule != null) {
          await MemoryLaneCacheService.instance.markScheduleCompletelySeen(
            schedule,
          );
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final toolbarTopPadding = widget.isFromMemoriesStrip
        ? math.max(40.0 - safePadding.top, 0.0) + 16
        : 16.0;
    return FutureBuilder<void>(
      future: _memoryLaneLoaded,
      builder: (context, snapshot) {
        final name = widget.person?.data.name.trim();
        var title = context.strings.facesTimelineAppBarTitle;
        if (name != null && name.isNotEmpty) {
          title = context.strings.memoryLaneCardTitle(
            name: name,
            nameEndsWithS: name.toLowerCase().endsWith("s").toString(),
          );
        }
        final file = _files.isEmpty ? null : _files[i];
        final entry = _entries.isEmpty ? null : _chunkinator!.get(_entries[i]);
        final creationTime = file?.creationTime;
        final creationDate = creationTime == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(creationTime);
        const captionPlaceholder = "\uFFFC";
        int? captionValue;
        String? caption;
        if (creationDate != null) {
          final now = DateTime.now();
          final today = DateTime.utc(now.year, now.month, now.day);
          final photoDate = DateTime.utc(
            creationDate.year,
            creationDate.month,
            creationDate.day,
          );
          var months =
              (now.year - creationDate.year) * 12 +
              now.month -
              creationDate.month;
          final anniversary = DateTime.utc(
            now.year,
            now.month,
            creationDate.day.clamp(
              1,
              DateTime.utc(now.year, now.month + 1, 0).day,
            ),
          );
          if (today.isBefore(anniversary)) months--;
          final days = today.difference(photoDate).inDays;
          if (months >= 12) {
            captionValue = months ~/ 12;
            caption = context.strings.memoryLaneCaptionYearsAgo(
              name: name ?? "",
              count: captionValue,
              number: captionPlaceholder,
            );
          } else if (months >= 1) {
            captionValue = months;
            caption = context.strings.memoryLaneCaptionMonthsAgo(
              name: name ?? "",
              count: captionValue,
              number: captionPlaceholder,
            );
          } else if (days >= 7) {
            captionValue = days ~/ 7;
            caption = context.strings.memoryLaneCaptionWeeksAgo(
              name: name ?? "",
              count: captionValue,
              number: captionPlaceholder,
            );
          } else if (days >= 1) {
            captionValue = days;
            caption = context.strings.memoryLaneCaptionDaysAgo(
              name: name ?? "",
              count: captionValue,
              number: captionPlaceholder,
            );
          } else {
            caption = context.strings.memoryLaneCaptionToday(name: name ?? "");
          }
          caption = caption.trim();
        }
        final captionParts =
            caption?.split(captionPlaceholder) ?? const <String>[];
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: AnimatedSwitcher(
                  duration: Duration(
                    milliseconds: _useFastTransition ? 100 : 750,
                  ),
                  switchInCurve: Curves.easeOutExpo,
                  switchOutCurve: Curves.easeInExpo,
                  child: FutureBuilder<(Uint8List, int)?>(
                    key: _currentEntryKey,
                    future: entry == null
                        ? null
                        : _fetchEntry(
                            entry,
                            const Size.square(256),
                            fitWithin: true,
                          ),
                    builder: (context, entrySnapshot) {
                      final crop = entrySnapshot.data;
                      if (crop == null) return const SizedBox.expand();
                      return ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                        child: Image.memory(
                          crop.$1,
                          cacheWidth: crop.$2,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (widget.isFromMemoriesStrip && _entries.isNotEmpty)
              Positioned(
                top: math.max(safePadding.top, 40),
                left: safePadding.left + 16,
                right: safePadding.right + 16,
                child: MemoryProgressIndicator(
                  totalSteps: _entries.length,
                  currentIndex: i,
                  duration: _playbackInterval,
                  unselectedColor: Colors.white.withValues(alpha: 0.4),
                  animationController: (controller) {
                    _progressAnimationController = controller;
                    controller.value =
                        (_playbackElapsed.elapsedMicroseconds /
                                _playbackInterval.inMicroseconds)
                            .clamp(0.0, 1.0);
                    if (_playbackElapsed.isRunning) controller.forward();
                  },
                  onAnimationControllerDisposed: (controller) {
                    if (_progressAnimationController == controller) {
                      _progressAnimationController = null;
                    }
                  },
                ),
              ),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(
                  kToolbarHeight + toolbarTopPadding,
                ),
                child: Padding(
                  padding: EdgeInsets.only(top: toolbarTopPadding),
                  child: AppBar(
                    centerTitle: false,
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    iconTheme: const IconThemeData(color: Colors.white),
                    actionsIconTheme: const IconThemeData(color: Colors.white),
                    systemOverlayStyle: SystemUiOverlayStyle.light,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hero(
                          tag: 'memory-lane-title-${widget.personId}',
                          child: Text(
                            title,
                            style: darkTheme.textTheme.large.copyWith(
                              inherit: false,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (file != null && creationTime != null)
                          GestureDetector(
                            onTap: () => _onDateTap(file),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat.yMMMMd(
                                    Localizations.localeOf(
                                      context,
                                    ).toLanguageTag(),
                                  ).format(
                                    DateTime.fromMicrosecondsSinceEpoch(
                                      creationTime,
                                    ),
                                  ),
                                  style: darkTheme.textTheme.small,
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    leadingWidth: 48 + screenSize.width * 0.04,
                    actionsPadding: EdgeInsets.only(
                      right: screenSize.width * 0.04,
                    ),
                    // TODO: Replace with an Ente component when it supports this pressed overlay.
                    leading: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          tooltip: context.strings.close,
                          style: IconButton.styleFrom(
                            overlayColor: Colors.white.withValues(alpha: 0.08),
                          ),
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    actions: [
                      if (widget.person != null &&
                          flagService.enableMemoryShareLink &&
                          !isLocalGalleryMode)
                        // TODO: Replace with an Ente component when it supports this pressed overlay.
                        SizedBox.square(
                          dimension: 48,
                          child: IconButton(
                            tooltip: context.strings.shareLink,
                            style: IconButton.styleFrom(
                              overlayColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                            ),
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedShare08,
                              color: Colors.white,
                            ),
                            onPressed: _onShareTap,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Listener(
                        onPointerDown: (event) {
                          if (_photoPointer != null || !widget.isActive) return;
                          _photoPointer = event.pointer;
                          _pause();
                        },
                        onPointerUp: _onPhotoPointerEnd,
                        onPointerCancel: _onPhotoPointerEnd,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) {
                            if (!widget.isActive || _entries.isEmpty) return;
                            final previous =
                                details.localPosition.dx < screenSize.width / 2;
                            final index = i + (previous ? -1 : 1);
                            if (index < 0 || index >= _entries.length) {
                              final onMemory = previous
                                  ? widget.onPreviousMemory
                                  : widget.onNextMemory;
                              if (onMemory != null) {
                                _pause();
                                onMemory();
                              }
                            } else {
                              unawaited(_play(index, fastTransition: true));
                            }
                          },
                          onLongPress: () {},
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: screenSize.width * 0.08,
                              vertical: screenSize.height * 0.02,
                            ),
                            child: Align(
                              child: AspectRatio(
                                aspectRatio: 3 / 4,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: AnimatedSwitcher(
                                    duration: Duration(
                                      milliseconds: _useFastTransition
                                          ? 100
                                          : 1000,
                                    ),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      return AnimatedBuilder(
                                        animation: animation,
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: 1,
                                              end: 1.1,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                        builder: (context, child) {
                                          final blur =
                                              12 * (1 - animation.value);
                                          return ImageFiltered(
                                            imageFilter: ImageFilter.blur(
                                              sigmaX: blur,
                                              sigmaY: blur,
                                            ),
                                            child: child,
                                          );
                                        },
                                      );
                                    },
                                    child: switch (snapshot.connectionState) {
                                      ConnectionState.done when file != null =>
                                        LayoutBuilder(
                                          key: _currentEntryKey,
                                          builder: (context, constraints) =>
                                              FutureBuilder<(Uint8List, int)?>(
                                                future: entry == null
                                                    ? null
                                                    : _fetchEntry(
                                                        entry,
                                                        constraints.biggest *
                                                            MediaQuery.devicePixelRatioOf(
                                                              context,
                                                            ) *
                                                            1.1,
                                                      ),
                                                builder: (context, entrySnapshot) {
                                                  final crop =
                                                      entrySnapshot.data;
                                                  if (crop == null) {
                                                    if (entrySnapshot
                                                            .connectionState ==
                                                        ConnectionState.done) {
                                                      return Center(
                                                        child: Text(
                                                          context
                                                              .strings
                                                              .facesTimelineUnavailable,
                                                          style: darkTheme
                                                              .textTheme
                                                              .small,
                                                        ),
                                                      );
                                                    }
                                                    return const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                            color: Colors.white,
                                                          ),
                                                    );
                                                  }
                                                  return Image.memory(
                                                    crop.$1,
                                                    cacheWidth: crop.$2,
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                  );
                                                },
                                              ),
                                        ),
                                      ConnectionState.done => Center(
                                        key: const ValueKey(
                                          "memory-lane-empty",
                                        ),
                                        child: Text(
                                          context
                                              .strings
                                              .facesTimelineUnavailable,
                                          style: darkTheme.textTheme.small,
                                        ),
                                      ),
                                      _ => const Center(
                                        key: ValueKey("memory-lane-loading"),
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                        ),
                                      ),
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: screenSize.height * 0.1,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (caption != null) ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  spacing: screenSize.width * 0.02,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < captionParts.length;
                                      index++
                                    ) ...[
                                      if (index > 0 && captionValue != null)
                                        _MemoryLaneAnimatedDigit(
                                          value: captionValue,
                                        ),
                                      Flexible(
                                        child: Text(
                                          captionParts[index],
                                          style: darkTheme.textTheme.bodyMuted,
                                          textAlign: TextAlign.center,
                                          softWrap: false,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: screenSize.height * 0.01),
                          ],
                          if (_entries.isNotEmpty &&
                              !widget.isFromMemoriesStrip)
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 32),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: screenSize.width * 0.16,
                                ),
                                child: Row(
                                  mainAxisAlignment: .center,
                                  children: [
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          const maxDotSize = 15.0;
                                          const dotSpacing = 5.0;
                                          final dotCount =
                                              ((constraints.maxWidth +
                                                          dotSpacing) /
                                                      (maxDotSize + dotSpacing))
                                                  .floor()
                                                  .clamp(1, _entries.length);
                                          final activeDot =
                                              i * dotCount ~/ _entries.length;
                                          return GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTapUp: (details) {
                                              if (constraints.maxWidth <= 0) {
                                                return;
                                              }
                                              final index =
                                                  (details.localPosition.dx /
                                                          constraints.maxWidth *
                                                          _entries.length)
                                                      .floor()
                                                      .clamp(
                                                        0,
                                                        _entries.length - 1,
                                                      );
                                              unawaited(
                                                _play(
                                                  index,
                                                  fastTransition: true,
                                                ),
                                              );
                                            },
                                            onHorizontalDragStart: (details) {
                                              _seekFromPosition(
                                                details.localPosition.dx,
                                                constraints.maxWidth,
                                              );
                                            },
                                            onHorizontalDragUpdate: (details) =>
                                                _seekFromPosition(
                                                  details.localPosition.dx,
                                                  constraints.maxWidth,
                                                ),
                                            onHorizontalDragEnd: (_) =>
                                                unawaited(_play(i)),
                                            onHorizontalDragCancel: () =>
                                                unawaited(_play(i)),
                                            child: Row(
                                              spacing: dotSpacing,
                                              children: List.generate(dotCount, (
                                                index,
                                              ) {
                                                final distance =
                                                    (index - activeDot).abs();
                                                final double size =
                                                    switch (distance) {
                                                      0 => maxDotSize,
                                                      1 => 10,
                                                      2 => 7.5,
                                                      _ => 5,
                                                    };
                                                return Expanded(
                                                  child: SizedBox(
                                                    height: 40,
                                                    child: Center(
                                                      child: AnimatedContainer(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 200,
                                                            ),
                                                        width: size,
                                                        height: size,
                                                        decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha:
                                                                    distance ==
                                                                        0
                                                                    ? 1
                                                                    : 0.5,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          SizedBox(height: screenSize.height * 0.055),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onShareTap() async {
    final timeline = _timeline;
    final person = widget.person;
    if (!flagService.enableMemoryShareLink ||
        isLocalGalleryMode ||
        timeline == null ||
        person == null ||
        !timeline.isEligible ||
        timeline.entries.isEmpty) {
      return;
    }
    final l10n = context.strings;
    final name = person.data.name.trim();
    var title = l10n.facesTimelineAppBarTitle;
    if (name.isNotEmpty) {
      title = l10n.memoryLaneCardTitle(
        name: name,
        nameEndsWithS: name.toLowerCase().endsWith("s").toString(),
      );
    }
    final dialog = createProgressDialog(context, l10n.creatingLink);
    final wasPlaying = _playbackToken != null;
    _pause();

    try {
      await dialog.show();
      final shareLinkData = await MemoryShareService.instance
          .getOrCreateMemoryLaneLink(
            entries: timeline.entries,
            title: title,
            personId: person.remoteID,
            personName: person.data.name,
            birthDate: person.data.birthDate,
          );
      await dialog.hide();
      if (!mounted) return;
      await shareText(
        formatMemoryShareText(title, shareLinkData.$1),
        context: context,
      );
    } catch (e) {
      await dialog.hide();
      if (!mounted) return;
      await showGenericErrorBottomSheet(context: context, error: e);
    } finally {
      if (mounted && wasPlaying && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_play(i));
      }
    }
  }

  Future<void> _onDateTap(EnteFile file) async {
    final wasPlaying = _playbackToken != null;
    _pause();
    try {
      await routeToPage(context, JumpToDateGallery(fileToJumpTo: file));
    } finally {
      if (mounted && wasPlaying && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_play(i));
      }
    }
  }
}

class _MemoryLaneAnimatedDigit extends StatefulWidget {
  const _MemoryLaneAnimatedDigit({required this.value}) : assert(value >= 0);

  final int value;

  @override
  State<_MemoryLaneAnimatedDigit> createState() =>
      _MemoryLaneAnimatedDigitState();
}

class _MemoryLaneAnimatedDigitState extends State<_MemoryLaneAnimatedDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(_MemoryLaneAnimatedDigit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _previousValue = oldWidget.value;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = widget.value >= _previousValue ? 1 : -1;
    final formatter = NumberFormat.decimalPattern(context.strings.localeName);
    final current = formatter.format(widget.value);
    final previous = formatter.format(_previousValue);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: current,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final progress = disableAnimations
              ? 1.0
              : Curves.easeOutCubic.transform(_controller.value);
          final length = progress == 1
              ? current.length
              : math.max(current.length, previous.length);
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            textDirection: TextDirection.ltr,
            children: [
              for (var place = length - 1; place >= 0; place--)
                Builder(
                  key: ValueKey(place),
                  builder: (context) {
                    final nextDigit = place < current.length
                        ? current[current.length - place - 1]
                        : null;
                    final oldDigit = place < previous.length
                        ? previous[previous.length - place - 1]
                        : null;
                    if (progress == 1 || oldDigit == nextDigit) {
                      return Text(
                        nextDigit ?? "",
                        style: darkTheme.textTheme.h2Bold,
                      );
                    }
                    return ClipRect(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (oldDigit != null)
                            FractionalTranslation(
                              translation: Offset(0, -direction * progress),
                              child: Text(
                                oldDigit,
                                style: darkTheme.textTheme.h2Bold,
                              ),
                            ),
                          if (nextDigit != null)
                            FractionalTranslation(
                              translation: Offset(
                                0,
                                direction * (1 - progress),
                              ),
                              child: Text(
                                nextDigit,
                                style: darkTheme.textTheme.h2Bold,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Chunkinator<K, V> {
  final List<K> keys;
  final Future<V> Function(K key) fetch;
  final int chunkSize;

  final Map<K, Future<V>> _cache = {};
  bool _disposed = false;

  _Chunkinator({required this.keys, required this.fetch, this.chunkSize = 5}) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(
        chunkSize,
        'chunkSize',
        'Must be greater than 0',
      );
    }
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
  }

  Future<V> get(K key) {
    if (_disposed) {
      throw StateError('Chunkinator is disposed');
    }
    final index = keys.indexOf(key);
    if (index == -1) {
      throw StateError('Key not found in keys: $key');
    }
    unawaited(_fetchChunk(index));
    return _cache[key]!;
  }

  Future<void> _fetchChunk(int start) async {
    if (start >= keys.length) {
      return;
    }
    final end = math.min(start + chunkSize, keys.length);
    while (start < end && _cache.containsKey(keys[start])) {
      start++;
    }
    for (var i = start; i < end; i++) {
      if (_disposed) return;
      final key = keys[i];
      try {
        await _cache.putIfAbsent(key, () => fetch(key));
      } catch (_) {}
    }
  }
}
