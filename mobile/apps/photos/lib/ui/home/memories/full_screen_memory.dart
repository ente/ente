import "dart:async";
import "dart:io";
import "dart:math";
import "dart:ui";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/details_sheet_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/events/reset_zoom_of_photo_view_event.dart";
import "package:photos/events/resume_video_event.dart";
import "package:photos/events/retry_failed_image_load_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/services/smart_memories_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/home/memories/custom_listener.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/home/memories/memory_share_sheet.dart";
import "package:photos/ui/home/memories/memory_video_prefetcher.dart";
import "package:photos/ui/viewer/file/file_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/file_details/favorite_widget.dart";
import "package:photos/ui/viewer/gallery/jump_to_date_gallery.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/share_util.dart";

//There are two states of variables that FullScreenMemory depends on:
//1. The list of memories
//2. The current index of the page view

//1
//Only when items are deleted will list of memories change and this requires the
//whole screen to be rebuild. So the InheritedWidget is updated using the Updater
//widget which will then lead to a rebuild of all widgets that call
//InheritedWidget.of(context).

//2
//There are widgets that doesn't come inside the PageView that needs to rebuild
//with new state when page index is changed. So the index is stored in a
//ValueNotifier inside the InheritedWidget and the widgets that need to change
//are wrapped in a ValueListenableBuilder.

//TODO: Use better naming convention. "Memory" should be a whole memory and
//parts of the memory should be called "items".
int? _clampedMemoryIndex(int index, int length) {
  if (length == 0) return null;
  return min(max(index, 0), length - 1);
}

bool _isValidMemoryIndex(int index, int length) {
  return index >= 0 && index < length;
}

class FullScreenMemoryDataUpdater extends StatefulWidget {
  final List<Memory> memories;
  final int initialIndex;
  final Widget child;
  const FullScreenMemoryDataUpdater({
    required this.memories,
    required this.initialIndex,
    required this.child,
    super.key,
  });

  @override
  State<FullScreenMemoryDataUpdater> createState() =>
      _FullScreenMemoryDataUpdaterState();
}

class _FullScreenMemoryDataUpdaterState
    extends State<FullScreenMemoryDataUpdater> {
  late ValueNotifier<int> indexNotifier;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final _ownedThumbnailRefs = <int, ({EnteFile file, Object token})>{};
  final _pendingThumbnailRefIDs = <int>{};
  final _videoPrefetcher = MemoryVideoPrefetcher();
  // Seeded from checkConnectivity() before the listener attaches, so a real
  // offline→online recovery (fire retry) is distinguishable from a WiFi↔
  // cellular handoff where the old requests are still healthy.
  bool _wasConnected = false;

  @override
  void initState() {
    super.initState();
    final initialIndex = _clampedMemoryIndex(
      widget.initialIndex,
      widget.memories.length,
    );
    indexNotifier = ValueNotifier(initialIndex ?? 0);
    if (initialIndex == null) return;
    memoriesCacheService.markMemoryAsSeen(
      widget.memories[initialIndex],
      widget.memories.length == initialIndex + 1,
    );
    _warmThumbnailWindow(initialIndex);
    _warmVideoWindow(initialIndex + 1);
    unawaited(_setupConnectivityListener());
  }

  @override
  void didUpdateWidget(covariant FullScreenMemoryDataUpdater oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _clampedMemoryIndex(
      indexNotifier.value,
      widget.memories.length,
    );
    final safeIndex = index ?? 0;
    if (indexNotifier.value != safeIndex) {
      indexNotifier.value = safeIndex;
    }
  }

  Future<void> _setupConnectivityListener() async {
    try {
      final initialResults = await Connectivity().checkConnectivity();
      _wasConnected = initialResults.any(
        (result) => result != ConnectivityResult.none,
      );
    } catch (_) {
      // Prefer a spurious retry over a missed one if the check fails.
      _wasConnected = false;
    }
    if (!mounted) return;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final hasConnection = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasConnection) {
        _wasConnected = false;
        return;
      }
      if (!_wasConnected) {
        _wasConnected = true;
        final currentIndex = indexNotifier.value;
        _releaseOwnedThumbnailRefs();
        Bus.instance.fire(RetryFailedImageLoadEvent());
        // Re-kick on a microtask so the event handler runs first and clears
        // the stale map entries; a synchronous call would re-bump the
        // refcounts before the cancellation.
        scheduleMicrotask(() {
          if (!mounted) return;
          _warmThumbnailWindow(currentIndex);
          _warmVideoWindow(currentIndex + 1);
        });
      }
    });
  }

  // Wide rolling window; thumbnails are tiny and gate the auto-advance timer.
  static const _thumbnailLookaheadCap = 20;

  // Narrow; originals are MBs each, this bounds concurrent bandwidth.
  static const _fileLookaheadCap = 3;

  void _warmThumbnailWindow(int fromIndex) {
    final start = fromIndex.clamp(0, widget.memories.length).toInt();
    final end = (start + _thumbnailLookaheadCap).clamp(
      0,
      widget.memories.length,
    );
    for (var i = start; i < end; i++) {
      _preloadThumbnailOwned(widget.memories[i].file);
    }
  }

  void _warmVideoWindow(int fromIndex) {
    final start = fromIndex.clamp(0, widget.memories.length).toInt();
    final end = (start + kMemoryVideoLookaheadCap)
        .clamp(0, widget.memories.length)
        .toInt();
    _videoPrefetcher.prefetchFiles(
      widget.memories.sublist(start, end).map((memory) => memory.file),
      replacePending: true,
    );
  }

  void _preloadThumbnailOwned(EnteFile file) {
    if (!file.isRemoteOnlyFile) {
      preloadThumbnail(file);
      return;
    }
    final uploadedFileID = file.uploadedFileID;
    if (uploadedFileID == null) {
      preloadThumbnail(file);
      return;
    }
    if (_ownedThumbnailRefs.containsKey(uploadedFileID) ||
        _pendingThumbnailRefIDs.contains(uploadedFileID)) {
      return;
    }
    _pendingThumbnailRefIDs.add(uploadedFileID);
    unawaited(_preloadRemoteThumbnailOwned(file, uploadedFileID));
  }

  Future<void> _preloadRemoteThumbnailOwned(
    EnteFile file,
    int uploadedFileID,
  ) async {
    try {
      final request = await preloadThumbnailWithPendingRequestRef(file);
      if (!request.acquiredPendingRequestRef) {
        return;
      }
      if (!mounted) {
        removePendingGetThumbnailRequestIfAny(file);
        return;
      }
      final token = Object();
      _ownedThumbnailRefs[uploadedFileID] = (file: file, token: token);
      unawaited(
        request.pendingRequest.whenComplete(() {
          final ref = _ownedThumbnailRefs[uploadedFileID];
          if (ref?.token == token) {
            _ownedThumbnailRefs.remove(uploadedFileID);
          }
        }),
      );
    } catch (_) {
      // Best-effort warmup; visible widgets perform their own load/error path.
    } finally {
      _pendingThumbnailRefIDs.remove(uploadedFileID);
    }
  }

  void _releaseOwnedThumbnailRefs() {
    for (final ref in _ownedThumbnailRefs.values) {
      removePendingGetThumbnailRequestIfAny(ref.file);
    }
    _ownedThumbnailRefs.clear();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _releaseOwnedThumbnailRefs();
    _videoPrefetcher.dispose();
    indexNotifier.dispose();
    super.dispose();
  }

  void removeCurrentMemory() {
    final removeIndex = _clampedMemoryIndex(
      indexNotifier.value,
      widget.memories.length,
    );
    if (removeIndex == null) return;
    widget.memories.removeAt(removeIndex);
    if (!mounted) return;
    setState(() {
      indexNotifier.value =
          _clampedMemoryIndex(removeIndex, widget.memories.length) ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    return FullScreenMemoryData(
      memories: widget.memories,
      indexNotifier: indexNotifier,
      removeCurrentMemory: removeCurrentMemory,
      preloadThumbnail: _preloadThumbnailOwned,
      preloadVideos: _warmVideoWindow,
      child: widget.child,
    );
  }
}

class FullScreenMemoryData extends InheritedWidget {
  final List<Memory> memories;
  final ValueNotifier<int> indexNotifier;
  final VoidCallback removeCurrentMemory;
  final void Function(EnteFile file) preloadThumbnail;
  final void Function(int fromIndex) preloadVideos;

  const FullScreenMemoryData({
    required this.memories,
    required this.indexNotifier,
    required this.removeCurrentMemory,
    required this.preloadThumbnail,
    required this.preloadVideos,
    required super.child,
    super.key,
  });

  static FullScreenMemoryData? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FullScreenMemoryData>();
  }

  @override
  bool updateShouldNotify(FullScreenMemoryData oldWidget) {
    // Checking oldWidget.memories.length != memories.length here doesn't work
    //because the old widget and new widget reference the same memories list.
    return true;
  }
}

class FullScreenMemory extends StatefulWidget {
  final String title;
  final int initialIndex;
  final VoidCallback? onNextMemory;
  final VoidCallback? onPreviousMemory;

  const FullScreenMemory(
    this.title,
    this.initialIndex, {
    this.onNextMemory,
    this.onPreviousMemory,
    super.key,
  });

  @override
  State<FullScreenMemory> createState() => _FullScreenMemoryState();
}

class _FullScreenMemoryState extends State<FullScreenMemory> {
  final _showTitle = ValueNotifier<bool>(true);
  AnimationController? _progressAnimationController;
  AnimationController? _zoomAnimationController;
  final ValueNotifier<Duration> durationNotifier = ValueNotifier(
    const Duration(seconds: 5),
  );
  // Differentiates the photo crossfade tempo: snappy for manual taps,
  // slower/cinematic for auto-advance. Set at the call site before the
  // index bump so AnimatedSwitcher reads the right duration on rebuild.
  bool _autoAdvanceTransition = false;
  // One-shot "curtain rises" fade on the first photo of a memory.
  // AnimatedSwitcher doesn't animate its initial child, so we wrap it
  // in an AnimatedOpacity that ramps 0→1 after the first frame.
  double _firstPhotoOpacity = 0;
  // Photo crossfade durations for auto vs manual advance.
  static const _autoCrossfadeDuration = Duration(milliseconds: 600);
  static const _manualCrossfadeDuration = Duration(milliseconds: 200);
  // How long to hold the incoming photo's Ken Burns still. Intentionally
  // shorter than _autoCrossfadeDuration so motion picks up as the photo
  // is still settling in, rather than after a visible beat of stillness.
  static const _kenBurnsFreezeDuration = Duration(milliseconds: 300);
  // Tokenises a pending zoom-start so a newer onFinalFileLoad cleanly
  // invalidates the prior delayed forward.
  Object? _kenBurnsStartToken;
  bool _isAnimationPaused = false;

  /// Used to check if any pointer is on the screen.
  final hasPointerOnScreenNotifier = ValueNotifier<bool>(false);
  bool hasFinalFileLoaded = false;
  bool isAtFirstOrLastFile = false;

  late final StreamSubscription<DetailsSheetEvent>
  _detailSheetEventSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _firstPhotoOpacity = 1);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _showTitle.value = false;
    });
    hasPointerOnScreenNotifier.addListener(_hasPointerListener);

    _detailSheetEventSubscription = Bus.instance.on<DetailsSheetEvent>().listen(
      (event) {
        if (!mounted) return;
        final inheritedData = FullScreenMemoryData.of(context);
        if (inheritedData == null) return;
        final index = inheritedData.indexNotifier.value;
        if (!_isValidMemoryIndex(index, inheritedData.memories.length)) {
          return;
        }
        final currentFile = inheritedData.memories[index].file;

        if (event.isSameFile(
          uploadedFileID: currentFile.uploadedFileID,
          localID: currentFile.localID,
        )) {
          _toggleAnimation(pause: event.opened);
        }
      },
    );
  }

  @override
  void dispose() {
    _showTitle.dispose();
    durationNotifier.dispose();
    hasPointerOnScreenNotifier.removeListener(_hasPointerListener);
    _detailSheetEventSubscription.cancel();
    _progressAnimationController = null;
    _zoomAnimationController = null;
    _kenBurnsStartToken = null;
    super.dispose();
  }

  /// Used to check if user has touched the screen and then to pause animation
  /// and once the pointer is removed from the screen, it resumes the animation
  /// It also resets the zoom of the photo view to default for better user
  /// experience after finger(s) is removed from the screen after zooming in by
  /// pinching.
  void _hasPointerListener() {
    if (hasPointerOnScreenNotifier.value) {
      _toggleAnimation(pause: true);
    } else {
      _toggleAnimation(pause: false);
      final inheritedData = FullScreenMemoryData.of(context);
      if (inheritedData == null) return;
      final index = inheritedData.indexNotifier.value;
      if (!_isValidMemoryIndex(index, inheritedData.memories.length)) return;
      final currentFile = inheritedData.memories[index].file;
      Bus.instance.fire(
        ResetZoomOfPhotoView(
          localID: currentFile.localID,
          uploadedFileID: currentFile.uploadedFileID,
        ),
      );
    }
  }

  void _toggleAnimation({required bool pause}) {
    if (!mounted) return;
    _isAnimationPaused = pause;
    if (pause) {
      _progressAnimationController?.stop();
      _zoomAnimationController?.stop();
    } else {
      if (hasFinalFileLoaded || isAtFirstOrLastFile) {
        _progressAnimationController?.forward();
        if (_kenBurnsStartToken == null) {
          _zoomAnimationController?.forward();
        }
      }
    }
  }

  void _resetAnimation() {
    if (!mounted) return;
    _progressAnimationController
      ?..stop()
      ..reset();
    _zoomAnimationController
      ?..stop()
      ..reset();
  }

  void _setProgressAnimationController(AnimationController controller) {
    _progressAnimationController = controller;
  }

  void _clearProgressAnimationController(AnimationController controller) {
    if (_progressAnimationController == controller) {
      _progressAnimationController = null;
    }
  }

  void _setZoomAnimationController(AnimationController controller) {
    // Freeze the outgoing photo's Ken Burns during auto-advance crossfades.
    if (_autoAdvanceTransition) {
      _zoomAnimationController?.stop();
    }
    _zoomAnimationController = controller;
  }

  void _clearZoomAnimationController(AnimationController controller) {
    if (_zoomAnimationController == controller) {
      _zoomAnimationController = null;
      _kenBurnsStartToken = null;
    }
  }

  void onFinalFileLoad(int duration) {
    if (!mounted) return;
    hasFinalFileLoaded = true;
    isAtFirstOrLastFile = false;
    if (_progressAnimationController?.isAnimating == true) {
      _progressAnimationController!.stop();
    }
    durationNotifier.value = Duration(seconds: duration);
    _progressAnimationController
      ?..stop()
      ..reset()
      ..duration = durationNotifier.value
      ..forward();
    _zoomAnimationController
      ?..stop()
      ..reset();
    if (_autoAdvanceTransition) {
      // Hold Ken Burns still during the incoming fade so its motion
      // doesn't compete with the outgoing photo's motion mid-overlap.
      final token = Object();
      _kenBurnsStartToken = token;
      final controller = _zoomAnimationController;
      Future.delayed(_kenBurnsFreezeDuration, () {
        if (!mounted) return;
        if (_kenBurnsStartToken != token) return;
        if (_zoomAnimationController != controller) return;
        _kenBurnsStartToken = null;
        if (_isAnimationPaused) return;
        controller?.forward();
      });
    } else {
      _kenBurnsStartToken = null;
      _zoomAnimationController?.forward();
    }
  }

  void _goToNext(FullScreenMemoryData inheritedData) {
    if (inheritedData.memories.isEmpty) return;
    hasFinalFileLoaded = false;
    final currentIndex = _clampedMemoryIndex(
      inheritedData.indexNotifier.value,
      inheritedData.memories.length,
    )!;
    inheritedData.indexNotifier.value = currentIndex;
    if (currentIndex < inheritedData.memories.length - 1) {
      inheritedData.indexNotifier.value += 1;
      _onPageChange(inheritedData, currentIndex + 1);
    } else if (widget.onNextMemory != null) {
      widget.onNextMemory!();
    } else {
      isAtFirstOrLastFile = true;
      _toggleAnimation(pause: false);
    }
  }

  void _goToPrevious(FullScreenMemoryData inheritedData) {
    if (inheritedData.memories.isEmpty) return;
    hasFinalFileLoaded = false;
    final currentIndex = _clampedMemoryIndex(
      inheritedData.indexNotifier.value,
      inheritedData.memories.length,
    )!;
    inheritedData.indexNotifier.value = currentIndex;
    if (currentIndex > 0) {
      inheritedData.indexNotifier.value -= 1;
      _onPageChange(inheritedData, currentIndex - 1);
    } else if (widget.onPreviousMemory != null) {
      widget.onPreviousMemory!();
    } else {
      isAtFirstOrLastFile = true;
      _resetAnimation();
      _toggleAnimation(pause: false);
    }
  }

  void _onPageChange(FullScreenMemoryData inheritedData, int index) {
    if (!_isValidMemoryIndex(index, inheritedData.memories.length)) return;
    isAtFirstOrLastFile = false;
    unawaited(
      memoriesCacheService.markMemoryAsSeen(
        inheritedData.memories[index],
        false,
      ),
    );
    inheritedData.indexNotifier.value = index;
    _resetAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final inheritedData = FullScreenMemoryData.of(context);
    if (inheritedData == null || inheritedData.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    final showStepProgressIndicator =
        inheritedData.memories.length < kMemoryProgressTickCutoff;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: strokeFainterDark, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Scaffold(
              backgroundColor: Colors.black,
              extendBodyBehindAppBar: true,
              appBar: AppBar(
                toolbarHeight: 64,
                primary: false,
                automaticallyImplyLeading: false,
                title: ValueListenableBuilder(
                  valueListenable: inheritedData.indexNotifier,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 8, 8),
                      child: Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                  builder: (context, value, child) {
                    final safeIndex = _clampedMemoryIndex(
                      value,
                      inheritedData.memories.length,
                    );
                    if (safeIndex == null) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 32),
                        ValueListenableBuilder<Duration>(
                          valueListenable: durationNotifier,
                          builder: (context, duration, _) {
                            return MemoryProgressIndicator(
                              totalSteps: inheritedData.memories.length,
                              currentIndex: safeIndex,
                              selectedColor: Colors.white,
                              unselectedColor: Colors.white.withValues(
                                alpha: 0.4,
                              ),
                              duration: duration,
                              animationController:
                                  _setProgressAnimationController,
                              onAnimationControllerDisposed:
                                  _clearProgressAnimationController,
                              onComplete: () {
                                _autoAdvanceTransition = true;
                                _goToNext(inheritedData);
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            child!,
                            GestureDetector(
                              onTap: () async {
                                final fullScreenState = context
                                    .findAncestorStateOfType<
                                      _FullScreenMemoryState
                                    >();
                                fullScreenState?._toggleAnimation(pause: true);
                                Bus.instance.fire(PauseVideoEvent());
                                await routeToPage(
                                  context,
                                  JumpToDateGallery(
                                    fileToJumpTo:
                                        inheritedData.memories[safeIndex].file,
                                  ),
                                );
                                Bus.instance.fire(ResumeVideoEvent());
                                fullScreenState?._toggleAnimation(pause: false);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  // color: fillFaintDark,
                                  color: blurStrokeFaintDark,
                                  border: Border.all(
                                    color: strokeFaintDark,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 2),
                                    Padding(
                                      padding: const EdgeInsets.all(2.0),
                                      child: Text(
                                        SmartMemoriesService.getDateFormatted(
                                          creationTime: inheritedData
                                              .memories[safeIndex]
                                              .file
                                              .creationTime!,
                                          context: context,
                                        ),
                                        style: getEnteTextTheme(context)
                                            .miniMuted
                                            .copyWith(color: textBaseDark),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.keyboard_arrow_right_outlined,
                                      size: 14,
                                      color: blurStrokeBaseDark,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                flexibleSpace: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.fromARGB(75, 0, 0, 0),
                        Color.fromARGB(37, 0, 0, 0),
                        Colors.transparent,
                        Colors.transparent,
                      ],
                      stops: [0, 0.45, 0.8, 1],
                    ),
                  ),
                ),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              body: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  const _MemoryBlur(),
                  ValueListenableBuilder<int>(
                    valueListenable: inheritedData.indexNotifier,
                    builder: (context, index, _) {
                      final safeIndex = _clampedMemoryIndex(
                        index,
                        inheritedData.memories.length,
                      );
                      if (safeIndex == null) return const SizedBox.shrink();
                      for (
                        var i = 1;
                        i <=
                            _FullScreenMemoryDataUpdaterState
                                ._thumbnailLookaheadCap;
                        i++
                      ) {
                        final j = safeIndex + i;
                        if (j >= inheritedData.memories.length) break;
                        inheritedData.preloadThumbnail(
                          inheritedData.memories[j].file,
                        );
                      }
                      for (
                        var i = 1;
                        i <=
                            _FullScreenMemoryDataUpdaterState._fileLookaheadCap;
                        i++
                      ) {
                        final j = safeIndex + i;
                        if (j >= inheritedData.memories.length) break;
                        preloadFile(inheritedData.memories[j].file);
                      }
                      inheritedData.preloadVideos(safeIndex + 1);
                      final currentMemory = inheritedData.memories[safeIndex];
                      final isVideo =
                          currentMemory.file.fileType == FileType.video;
                      final currentFile = currentMemory.file;

                      return MemoriesPointerGestureListener(
                        onTap: (PointerEvent event) {
                          _autoAdvanceTransition = false;
                          HapticFeedback.selectionClick();
                          final screenWidth = MediaQuery.sizeOf(context).width;
                          final goToPreviousTapAreaWidth = screenWidth * 0.20;
                          if (event.localPosition.dx <
                              goToPreviousTapAreaWidth) {
                            _goToPrevious(inheritedData);
                          } else {
                            _goToNext(inheritedData);
                          }
                        },
                        hasPointerNotifier: hasPointerOnScreenNotifier,
                        child: AnimatedOpacity(
                          opacity: _firstPhotoOpacity,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          child: AnimatedSwitcher(
                            duration: _autoAdvanceTransition
                                ? _autoCrossfadeDuration
                                : _manualCrossfadeDuration,
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                fit: StackFit.expand,
                                children: [...previousChildren, ?currentChild],
                              );
                            },
                            child: MemoriesZoomWidget(
                              key: ValueKey(
                                currentFile.uploadedFileID ??
                                    currentFile.localID,
                              ),
                              scaleController: _setZoomAnimationController,
                              onScaleControllerDisposed:
                                  _clearZoomAnimationController,
                              zoomIn: safeIndex % 2 == 0,
                              isVideo: isVideo,
                              child: FileWidget(
                                currentFile,
                                autoPlay: false,
                                tagPrefix: "memories",
                                backgroundDecoration: const BoxDecoration(
                                  color: Colors.transparent,
                                ),
                                isFromMemories: true,
                                playbackCallback: (shouldEnable, _) {
                                  _toggleAnimation(pause: !shouldEnable);
                                },
                                onFinalFileLoad:
                                    ({required int memoryDuration}) {
                                      onFinalFileLoad(memoryDuration);
                                    },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  BottomGradient(showTitle: _showTitle),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder(
                        valueListenable: _showTitle,
                        builder: (context, value, _) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: value
                                ? Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      32,
                                      4,
                                      32,
                                      12,
                                    ),
                                    child: Hero(
                                      tag: widget.title,
                                      child: Text(
                                        widget.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 30,
                                          fontFamily: "Montserrat",
                                        ),
                                        textAlign: TextAlign.left,
                                      ),
                                    ),
                                  )
                                : showStepProgressIndicator
                                ? const SizedBox.shrink()
                                : const MemoryCounter(),
                          );
                        },
                      ),
                      const BottomIcons(),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BottomIcons extends StatelessWidget {
  const BottomIcons({super.key});

  @override
  Widget build(BuildContext context) {
    final inheritedData = FullScreenMemoryData.of(context);
    if (inheritedData == null || inheritedData.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    final fullScreenState = context
        .findAncestorStateOfType<_FullScreenMemoryState>();
    final memoryTitle =
        context.findAncestorWidgetOfExactType<FullScreenMemory>()?.title ??
        AppLocalizations.of(context).memories;

    return ValueListenableBuilder(
      valueListenable: inheritedData.indexNotifier,
      builder: (context, value, _) {
        final safeIndex = _clampedMemoryIndex(
          value,
          inheritedData.memories.length,
        );
        if (safeIndex == null) return const SizedBox.shrink();
        final currentFile = inheritedData.memories[safeIndex].file;
        final List<Widget> rowChildren = [
          IconButton(
            icon: Icon(
              Platform.isAndroid ? Icons.info_outline : CupertinoIcons.info,
              color: Colors.white, //same for both themes
            ),
            onPressed: () async {
              fullScreenState?._toggleAnimation(pause: true);
              await showDetailsSheet(context, currentFile);
              fullScreenState?._toggleAnimation(pause: false);
            },
          ),
        ];

        final isOwner =
            currentFile.ownerID == null ||
            (Configuration.instance.getUserID() ?? 0) == currentFile.ownerID;
        if (isOwner) {
          rowChildren.addAll([
            IconButton(
              icon: Icon(
                Platform.isAndroid
                    ? Icons.delete_outline
                    : CupertinoIcons.delete,
                color: Colors.white, //same for both themes
              ),
              onPressed: () async {
                final currentIndex = _clampedMemoryIndex(
                  inheritedData.indexNotifier.value,
                  inheritedData.memories.length,
                );
                if (currentIndex == null) return;
                fullScreenState?._toggleAnimation(pause: true);
                await showSingleFileDeleteSheet(
                  context,
                  inheritedData.memories[currentIndex].file,
                  onFileRemoved: (file) => {
                    inheritedData.removeCurrentMemory.call(),
                    if (inheritedData.memories.isEmpty)
                      {Navigator.of(context).pop()},
                  },
                );
                fullScreenState?._toggleAnimation(pause: false);
              },
            ),
          ]);
          if (!isLocalGalleryMode) {
            rowChildren.add(
              SizedBox(height: 32, child: FavoriteWidget(currentFile)),
            );
          }
        }
        rowChildren.add(
          IconButton(
            icon: Icon(
              Icons.adaptive.share,
              color: Colors.white, //same for both themes
            ),
            onPressed: () async {
              fullScreenState?._toggleAnimation(pause: true);
              await _shareMemory(context, inheritedData, memoryTitle);
              fullScreenState?._toggleAnimation(pause: false);
            },
          ),
        );
        return Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: rowChildren,
          ),
        );
      },
    );
  }
}

class MemoryCounter extends StatelessWidget {
  const MemoryCounter({super.key});

  @override
  Widget build(BuildContext context) {
    final inheritedData = FullScreenMemoryData.of(context);
    if (inheritedData == null || inheritedData.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder(
      valueListenable: inheritedData.indexNotifier,
      builder: (context, value, _) {
        final safeIndex = _clampedMemoryIndex(
          value,
          inheritedData.memories.length,
        );
        if (safeIndex == null) return const SizedBox.shrink();
        return Text(
          "${safeIndex + 1}/${inheritedData.memories.length}",
          style: darkTextTheme.bodyMuted,
        );
      },
    );
  }
}

class BottomGradient extends StatelessWidget {
  final ValueNotifier<bool> showTitle;
  const BottomGradient({super.key, required this.showTitle});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: showTitle,
        builder: (context, value, _) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 875),
            curve: Curves.easeOutQuart,
            height: value ? 240 : 120,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color.fromARGB(97, 0, 0, 0),
                  Color.fromARGB(42, 0, 0, 0),
                  Colors.transparent,
                ],
                stops: [0, 0.5, 1.0],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MemoryBlur extends StatelessWidget {
  const _MemoryBlur();

  @override
  Widget build(BuildContext context) {
    final inheritedData = FullScreenMemoryData.of(context);
    if (inheritedData == null || inheritedData.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder(
      valueListenable: inheritedData.indexNotifier,
      builder: (context, value, _) {
        final safeIndex = _clampedMemoryIndex(
          value,
          inheritedData.memories.length,
        );
        if (safeIndex == null) return const SizedBox.shrink();
        final currentFile = inheritedData.memories[safeIndex].file;
        if (currentFile.fileType == FileType.video) {
          return const SizedBox.shrink();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 750),
          switchInCurve: Curves.easeOutExpo,
          switchOutCurve: Curves.easeInExpo,
          child: ImageFiltered(
            key: ValueKey(safeIndex),
            imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
            child: ThumbnailWidget(
              currentFile,
              placeholderColor: Colors.black,
              shouldShowSyncStatus: false,
              shouldShowFavoriteIcon: false,
              shouldShowVideoOverlayIcon: false,
            ),
          ),
        );
      },
    );
  }
}

class MemoriesZoomWidget extends StatefulWidget {
  final Widget child;
  final bool isVideo;
  final void Function(AnimationController)? scaleController;
  final void Function(AnimationController)? onScaleControllerDisposed;
  final bool zoomIn;

  const MemoriesZoomWidget({
    super.key,
    required this.child,
    required this.isVideo,
    required this.zoomIn,
    this.scaleController,
    this.onScaleControllerDisposed,
  });

  @override
  State<MemoriesZoomWidget> createState() => _MemoriesZoomWidgetState();
}

class _MemoriesZoomWidgetState extends State<MemoriesZoomWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _panAnimation;
  Random random = Random();

  @override
  void initState() {
    super.initState();
    _initAnimation();
  }

  void _initAnimation() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
      animationBehavior: AnimationBehavior.preserve,
    );

    final startScale = widget.zoomIn ? 1.05 : 1.15;
    final endScale = widget.zoomIn ? 1.15 : 1.05;

    final startX = (random.nextDouble() - 0.5) * 0.1;
    final startY = (random.nextDouble() - 0.5) * 0.1;
    final endX = (random.nextDouble() - 0.5) * 0.1;
    final endY = (random.nextDouble() - 0.5) * 0.1;

    _scaleAnimation = Tween<double>(
      begin: startScale,
      end: endScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _panAnimation = Tween<Offset>(
      begin: Offset(startX, startY),
      end: Offset(endX, endY),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.scaleController != null) {
      widget.scaleController!(_controller);
    }
  }

  @override
  void dispose() {
    widget.onScaleControllerDisposed?.call(_controller);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isVideo
        ? widget.child
        : ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              child: widget.child,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Transform.translate(
                    offset: Offset(
                      _panAnimation.value.dx * 100,
                      _panAnimation.value.dy * 100,
                    ),
                    child: child,
                  ),
                );
              },
            ),
          );
  }
}

Future<void> _shareMemory(
  BuildContext context,
  FullScreenMemoryData inheritedData,
  String memoryTitle,
) async {
  if (inheritedData.memories.isEmpty) return;
  final currentIndex = _clampedMemoryIndex(
    inheritedData.indexNotifier.value,
    inheritedData.memories.length,
  );
  if (currentIndex == null) return;
  final canShowMemoryShareLinkOption =
      flagService.enableMemoryShareLink &&
      !(isLocalGalleryMode && !Configuration.instance.hasConfiguredAccount());
  final result = await showMemoryShareSelectionSheet(
    context,
    memories: inheritedData.memories,
    initialIndex: currentIndex,
    canShareMemoryLink: canShowMemoryShareLinkOption,
  );
  if (!context.mounted || result == null) {
    return;
  }

  switch (result.action) {
    case MemoryShareSheetAction.shareMemory:
      final shareLinkData = await _getOrCreateMemoryLink(
        context,
        result.selectedMemories,
        memoryTitle,
      );
      if (!context.mounted || shareLinkData == null) {
        return;
      }
      await shareText(shareLinkData.$1, context: context);
      return;
    case MemoryShareSheetAction.shareItems:
      await share(context, Memory.filesFromMemories(result.selectedMemories));
  }
}

Future<(String, int)?> _getOrCreateMemoryLink(
  BuildContext context,
  List<Memory> memories,
  String memoryTitle,
) async {
  if (memories.isEmpty) return null;
  final l10n = AppLocalizations.of(context);
  final dialog = createProgressDialog(context, l10n.creatingLink);
  await dialog.show();
  try {
    final normalizedTitle = memoryTitle.trim();
    final shareLinkData = await MemoryShareService.instance
        .getOrCreateMemoryLink(
          memories: memories,
          title: normalizedTitle.isNotEmpty ? normalizedTitle : l10n.memories,
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
