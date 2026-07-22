import "dart:async";
import "dart:math";
import "dart:ui";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:ente_components/theme/text_styles.dart" as component;
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart" show ValueListenable;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/details_sheet_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/events/reset_zoom_of_photo_view_event.dart";
import "package:photos/events/resume_video_event.dart";
import "package:photos/events/retry_failed_image_load_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/services/smart_memories_service.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/home/memories/custom_listener.dart";
import "package:photos/ui/home/memories/memory_progress_indicator.dart";
import "package:photos/ui/home/memories/memory_share_sheet.dart";
import "package:photos/ui/home/memories/memory_video_prefetcher.dart";
import "package:photos/ui/home/memories/memory_viewer_constants.dart";
import "package:photos/ui/social/widgets/file_social_overlay.dart";
import "package:photos/ui/viewer/file/file_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/file_details/favorite_widget.dart";
import "package:photos/ui/viewer/gallery/jump_to_date_gallery.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/share_util.dart";

const _socialRightInset = 24.0;
const _socialToActionBarGap = 38.0;

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
  AnimationController? _progressAnimationController;
  AnimationController? _zoomAnimationController;
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
  bool _isViewerPaused = false;
  bool _isPlaybackPaused = false;
  bool get _isAnimationPaused => _isViewerPaused || _isPlaybackPaused;
  bool _isMediaZoomed = false;
  final _socialControlsVisible = ValueNotifier<bool>(false);

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
    hasPointerOnScreenNotifier.removeListener(_hasPointerListener);
    _detailSheetEventSubscription.cancel();
    _socialControlsVisible.dispose();
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
    _isViewerPaused = pause;
    _syncAnimationState();
  }

  void _togglePlaybackAnimation({required bool pause}) {
    if (!mounted) return;
    _isPlaybackPaused = pause;
    _syncAnimationState();
  }

  void _syncAnimationState() {
    if (_isAnimationPaused) {
      _progressAnimationController?.stop();
      _zoomAnimationController?.stop();
    } else if (hasFinalFileLoaded || isAtFirstOrLastFile) {
      _progressAnimationController?.forward();
      if (_kenBurnsStartToken == null) {
        _zoomAnimationController?.forward();
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
    _isPlaybackPaused = false;
    hasFinalFileLoaded = true;
    isAtFirstOrLastFile = false;
    final memoryDuration = Duration(seconds: duration);
    _progressAnimationController
      ?..stop()
      ..reset()
      ..duration = memoryDuration;
    if (!_isAnimationPaused) {
      _progressAnimationController?.forward();
    }
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
      if (!_isAnimationPaused) {
        _zoomAnimationController?.forward();
      }
    }
  }

  void _goToNext(FullScreenMemoryData inheritedData) {
    if (inheritedData.memories.isEmpty) return;
    _isMediaZoomed = false;
    hasFinalFileLoaded = false;
    final currentIndex = _clampedMemoryIndex(
      inheritedData.indexNotifier.value,
      inheritedData.memories.length,
    )!;
    inheritedData.indexNotifier.value = currentIndex;
    if (currentIndex < inheritedData.memories.length - 1) {
      _onPageChange(inheritedData, currentIndex + 1);
    } else if (widget.onNextMemory != null) {
      _resetAnimation();
      _setSocialControlsVisible(false);
      widget.onNextMemory!();
    } else {
      isAtFirstOrLastFile = true;
      _toggleAnimation(pause: false);
    }
  }

  void _goToPrevious(FullScreenMemoryData inheritedData) {
    if (inheritedData.memories.isEmpty) return;
    _isMediaZoomed = false;
    hasFinalFileLoaded = false;
    final currentIndex = _clampedMemoryIndex(
      inheritedData.indexNotifier.value,
      inheritedData.memories.length,
    )!;
    inheritedData.indexNotifier.value = currentIndex;
    if (currentIndex > 0) {
      _onPageChange(inheritedData, currentIndex - 1);
    } else if (widget.onPreviousMemory != null) {
      _resetAnimation();
      _setSocialControlsVisible(false);
      widget.onPreviousMemory!();
    } else {
      isAtFirstOrLastFile = true;
      _resetAnimation();
      _toggleAnimation(pause: false);
    }
  }

  void _onPageChange(FullScreenMemoryData inheritedData, int index) {
    if (!_isValidMemoryIndex(index, inheritedData.memories.length)) return;
    _isMediaZoomed = false;
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

  void _setSocialControlsVisible(bool visible) {
    if (_socialControlsVisible.value != visible) {
      _socialControlsVisible.value = visible;
    }
  }

  Future<T?> _runWithViewerPaused<T>(Future<T> Function() action) async {
    if (!mounted) return null;
    _pauseViewer();
    try {
      return await action();
    } finally {
      _resumeViewer();
    }
  }

  void _pauseViewer() {
    if (!mounted) return;
    _toggleAnimation(pause: true);
    Bus.instance.fire(PauseVideoEvent());
  }

  void _resumeViewer() {
    if (!mounted) return;
    Bus.instance.fire(ResumeVideoEvent());
    _toggleAnimation(pause: false);
  }

  @override
  Widget build(BuildContext context) {
    final inheritedData = FullScreenMemoryData.of(context);
    if (inheritedData == null || inheritedData.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
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
                  i <= _FullScreenMemoryDataUpdaterState._thumbnailLookaheadCap;
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
                  i <= _FullScreenMemoryDataUpdaterState._fileLookaheadCap;
                  i++
                ) {
                  final j = safeIndex + i;
                  if (j >= inheritedData.memories.length) break;
                  preloadFile(inheritedData.memories[j].file);
                }
                inheritedData.preloadVideos(safeIndex + 1);
                final currentMemory = inheritedData.memories[safeIndex];
                final isVideo = currentMemory.file.fileType == FileType.video;
                final currentFile = currentMemory.file;

                return MemoriesPointerGestureListener(
                  onTap: (PointerEvent event) {
                    _autoAdvanceTransition = false;
                    HapticFeedback.selectionClick();
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    final goToPreviousTapAreaWidth = screenWidth * 0.20;
                    if (event.localPosition.dx < goToPreviousTapAreaWidth) {
                      _goToPrevious(inheritedData);
                    } else {
                      _goToNext(inheritedData);
                    }
                  },
                  onSwipeUp: () {
                    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
                    _runWithViewerPaused(
                      () => showDetailsSheet(context, currentFile),
                    );
                  },
                  canSwipeUp: () => !_isMediaZoomed,
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
                          currentFile.uploadedFileID ?? currentFile.localID,
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
                          shouldDisableScroll: (isZoomed) {
                            _isMediaZoomed = isZoomed;
                          },
                          playbackCallback: (shouldEnable, _) {
                            final activeIndex = _clampedMemoryIndex(
                              inheritedData.indexNotifier.value,
                              inheritedData.memories.length,
                            );
                            if (activeIndex == null ||
                                inheritedData.memories[activeIndex].file !=
                                    currentFile) {
                              return;
                            }
                            _togglePlaybackAnimation(pause: !shouldEnable);
                          },
                          onFinalFileLoad: ({required int memoryDuration}) {
                            final activeIndex = _clampedMemoryIndex(
                              inheritedData.indexNotifier.value,
                              inheritedData.memories.length,
                            );
                            if (activeIndex == null ||
                                inheritedData.memories[activeIndex].file !=
                                    currentFile) {
                              return;
                            }
                            onFinalFileLoad(memoryDuration);
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            _MemoryViewerScrims(socialControlsVisible: _socialControlsVisible),
            ValueListenableBuilder<int>(
              valueListenable: inheritedData.indexNotifier,
              builder: (context, index, _) {
                final safeIndex = _clampedMemoryIndex(
                  index,
                  inheritedData.memories.length,
                );
                if (safeIndex == null) return const SizedBox.shrink();
                final padding = MediaQuery.paddingOf(context);
                return Positioned(
                  right: padding.right + _socialRightInset,
                  bottom:
                      padding.bottom +
                      kMemoryBottomActionBarHeight +
                      _socialToActionBarGap,
                  child: FileSocialOverlay(
                    file: inheritedData.memories[safeIndex].file,
                    currentUserID: Configuration.instance.getUserID(),
                    openingCollectionID: null,
                    onInteractionStart: _pauseViewer,
                    onInteractionEnd: _resumeViewer,
                    onVisibilityChanged: _setSocialControlsVisible,
                  ),
                );
              },
            ),
            const BottomIcons(),
            _MemoryTopOverlay(
              title: widget.title,
              onClose: () => Navigator.pop(context),
              onDateTap: (file) {
                _runWithViewerPaused(
                  () => routeToPage(
                    context,
                    JumpToDateGallery(fileToJumpTo: file),
                  ),
                );
              },
              animationController: _setProgressAnimationController,
              onAnimationControllerDisposed: _clearProgressAnimationController,
              onComplete: () {
                _autoAdvanceTransition = true;
                _goToNext(inheritedData);
              },
            ),
          ],
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

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ValueListenableBuilder(
        valueListenable: inheritedData.indexNotifier,
        builder: (context, value, _) {
          final safeIndex = _clampedMemoryIndex(
            value,
            inheritedData.memories.length,
          );
          if (safeIndex == null) return const SizedBox.shrink();
          final currentFile = inheritedData.memories[safeIndex].file;
          if (fullScreenState == null) return const SizedBox.shrink();

          final l10n = AppLocalizations.of(context);
          final isOwner = currentFile.isOwner;
          final collection = currentFile.collectionID == null
              ? null
              : collectionsService.getCollectionByID(currentFile.collectionID!);
          final isHidden =
              currentFile.isUploaded && (collection?.isHidden() ?? false);
          final rowChildren = <Widget>[
            _MemoryActionButton(
              tooltip: l10n.info,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedInformationCircle,
                color: Colors.white,
                size: 24,
              ),
              onPressed: () async {
                await fullScreenState._runWithViewerPaused(
                  () => showDetailsSheet(context, currentFile),
                );
              },
            ),
            _MemoryActionButton(
              tooltip: l10n.share,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedShare08,
                color: Colors.white,
                size: 24,
              ),
              onPressed: () async {
                await fullScreenState._runWithViewerPaused(
                  () => _shareMemory(context, inheritedData, memoryTitle),
                );
              },
            ),
            if (currentFile.isUploaded && !isHidden)
              _MemoryActionButton(
                tooltip: l10n.addToAlbum,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedAddSquare,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () async {
                  await fullScreenState._runWithViewerPaused(() async {
                    final selectedFiles = SelectedFiles();
                    selectedFiles.files.add(currentFile);
                    await showCollectionActionSheet(
                      context,
                      selectedFiles: selectedFiles,
                      actionType: CollectionActionType.addFiles,
                    );
                  });
                },
              ),
            if (isOwner)
              _MemoryActionButton(
                tooltip: l10n.delete,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () async {
                  await fullScreenState._runWithViewerPaused(() async {
                    final actionIndex = _clampedMemoryIndex(
                      inheritedData.indexNotifier.value,
                      inheritedData.memories.length,
                    );
                    if (actionIndex == null) return;
                    final actionFile = inheritedData.memories[actionIndex].file;
                    if (!actionFile.isOwner) return;
                    var shouldCloseViewer = false;
                    await showSingleFileDeleteSheet(
                      context,
                      actionFile,
                      onFileRemoved: (file) {
                        fullScreenState._setSocialControlsVisible(false);
                        fullScreenState.hasFinalFileLoaded = false;
                        fullScreenState._resetAnimation();
                        inheritedData.removeCurrentMemory();
                        shouldCloseViewer = inheritedData.memories.isEmpty;
                      },
                    );
                    if (shouldCloseViewer && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  });
                },
              ),
          ];
          final safePadding = MediaQuery.paddingOf(context);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              safePadding.left + 24,
              20,
              safePadding.right + 24,
              safePadding.bottom + 12,
            ),
            child: Row(
              children: rowChildren
                  .map((child) => Expanded(child: Center(child: child)))
                  .toList(growable: false),
            ),
          );
        },
      ),
    );
  }
}

class _MemoryActionButton extends StatelessWidget {
  final String tooltip;
  final Widget icon;
  final Future<void> Function() onPressed;

  const _MemoryActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        padding: const EdgeInsets.all(12),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          maximumSize: const Size.square(48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: Colors.white.withValues(alpha: 0.08),
        ),
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }
}

class _MemoryTopOverlay extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final ValueChanged<EnteFile> onDateTap;
  final void Function(AnimationController) animationController;
  final void Function(AnimationController) onAnimationControllerDisposed;
  final VoidCallback onComplete;

  const _MemoryTopOverlay({
    required this.title,
    required this.onClose,
    required this.onDateTap,
    required this.animationController,
    required this.onAnimationControllerDisposed,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final inheritedData = FullScreenMemoryData.of(context);
    if (inheritedData == null || inheritedData.memories.isEmpty) {
      return const SizedBox.shrink();
    }
    final safePadding = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ValueListenableBuilder<int>(
        valueListenable: inheritedData.indexNotifier,
        builder: (context, index, _) {
          final safeIndex = _clampedMemoryIndex(
            index,
            inheritedData.memories.length,
          );
          if (safeIndex == null) return const SizedBox.shrink();
          final currentFile = inheritedData.memories[safeIndex].file;
          final showFavorite = currentFile.isOwner && !isLocalGalleryMode;
          return Padding(
            padding: EdgeInsets.only(top: max(safePadding.top, 40)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    safePadding.left + 16,
                    0,
                    safePadding.right + 16,
                    0,
                  ),
                  child: MemoryProgressIndicator(
                    totalSteps: inheritedData.memories.length,
                    currentIndex: safeIndex,
                    selectedColor: Colors.white,
                    unselectedColor: Colors.white.withValues(alpha: 0.4),
                    animationController: animationController,
                    onAnimationControllerDisposed:
                        onAnimationControllerDisposed,
                    onComplete: onComplete,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    safePadding.left + 16,
                    0,
                    safePadding.right + 16,
                    0,
                  ),
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 48,
                          child: IconButton(
                            tooltip: AppLocalizations.of(context).close,
                            padding: const EdgeInsets.all(8),
                            style: IconButton.styleFrom(
                              minimumSize: const Size.square(48),
                              maximumSize: const Size.square(48),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              overlayColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                            ),
                            onPressed: onClose,
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onDateTap(currentFile),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Hero(
                                  tag: title,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: component.TextStyles.display3
                                        .copyWith(color: Colors.white),
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        SmartMemoriesService.getDateFormatted(
                                          creationTime:
                                              currentFile.creationTime!,
                                          context: context,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: component.TextStyles.mini
                                            .copyWith(color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 4,
                                      height: 8,
                                      child: CustomPaint(
                                        painter: _MemoryDateChevronPainter(),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showFavorite) ...[
                          const SizedBox(width: 8),
                          FavoriteWidget(
                            currentFile,
                            iconSize: 24,
                            tapTargetSize: 48,
                            key: ValueKey(
                              currentFile.uploadedFileID ?? currentFile.localID,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MemoryDateChevronPainter extends CustomPainter {
  const _MemoryDateChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(0.5, 0.5)
      ..lineTo(size.width - 0.5, size.height / 2)
      ..lineTo(0.5, size.height - 0.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MemoryViewerScrims extends StatelessWidget {
  final ValueListenable<bool> socialControlsVisible;

  const _MemoryViewerScrims({required this.socialControlsVisible});

  @override
  Widget build(BuildContext context) {
    final topHeight = MediaQuery.paddingOf(context).top + 104;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: double.infinity,
              height: topHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB8000000),
                      Color(0x70000000),
                      Colors.transparent,
                    ],
                    stops: [0, 0.6, 1],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<bool>(
              valueListenable: socialControlsVisible,
              builder: (context, isVisible, _) {
                final bottomInset = MediaQuery.paddingOf(context).bottom;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: double.infinity,
                  height: isVisible
                      ? kMemorySocialScrimHeight
                      : bottomInset + kMemoryBottomActionBarHeight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color.fromARGB(97, 0, 0, 0),
                        Color.fromARGB(42, 0, 0, 0),
                        Colors.transparent,
                      ],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
    return ValueListenableBuilder<int>(
      valueListenable: inheritedData.indexNotifier,
      builder: (context, index, _) {
        final safeIndex = _clampedMemoryIndex(
          index,
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
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            );
          },
          child: ImageFiltered(
            key: ValueKey(
              "memory-blur-${currentFile.uploadedFileID ?? currentFile.localID ?? safeIndex}",
            ),
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
