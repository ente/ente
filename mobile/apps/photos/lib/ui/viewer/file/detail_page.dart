import "dart:async";
import "dart:io";
import "dart:math";

import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:extended_image/extended_image.dart';
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import "package:flutter_svg/flutter_svg.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/events/file_caption_updated_event.dart";
import "package:photos/events/guest_view_event.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";
import "package:photos/models/gallery_type.dart";
import 'package:photos/module/download/file.dart';
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/common/fast_scroll_physics.dart";
import 'package:photos/ui/notification/toast.dart';
import "package:photos/ui/social/widgets/file_social_overlay.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_page.dart";
import "package:photos/ui/tools/editor/video_editor_page.dart";
import "package:photos/ui/viewer/file/file_app_bar.dart";
import "package:photos/ui/viewer/file/file_bottom_bar.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_coordinator.dart";
import 'package:photos/ui/viewer/file/file_widget.dart';
import "package:photos/ui/viewer/file/gallery_file_viewer_filmstrip.dart";
import "package:photos/ui/viewer/file/ocr/inline_text_detection.dart";
import "package:photos/ui/viewer/file/panorama_viewer_screen.dart";
import "package:photos/ui/viewer/file/qr_code_detection_helper.dart";
import "package:photos/ui/viewer/file/qr_code_highlight_overlay.dart";
import "package:photos/ui/viewer/file/video_control/gallery_video_controls.dart";
import "package:photos/ui/viewer/file/video_stream_change.dart";
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/utils/dialog_util.dart';

const _socialRightInset = 24.0;
const _socialBottomBarClearance = 130.0;
const _videoStreamControlHeight = 32.0;
const _galleryBottomBarHeight = 60.0;
const _galleryCaptionGap = 12.0;
const _galleryCaptionLineHeight = 16.0;
const _galleryCaptionScrimTopPadding = 12.0;

enum DetailPageMode { minimalistic, full }

class DetailPageConfiguration {
  final List<EnteFile> files;
  final int selectedIndex;
  final String tagPrefix;
  final DetailPageMode mode;
  final bool isLocalOnlyContext;
  final bool showEditAction;
  final bool showGalleryFilmstrip;
  final GalleryType? galleryType;
  final FutureOr<void> Function(BuildContext context)? onBackPressed;

  final void Function(BuildContext context)? onPageReady;

  DetailPageConfiguration(
    this.files,
    this.selectedIndex,
    this.tagPrefix, {
    this.mode = DetailPageMode.full,
    this.isLocalOnlyContext = false,
    this.showEditAction = true,
    this.showGalleryFilmstrip = false,
    this.galleryType,
    this.onBackPressed,
    this.onPageReady,
  });

  DetailPageConfiguration copyWith({
    List<EnteFile>? files,
    GalleryLoader? asyncLoader,
    int? selectedIndex,
    String? tagPrefix,
    DetailPageMode? mode,
    bool? isLocalOnlyContext,
    bool? showEditAction,
    bool? showGalleryFilmstrip,
    GalleryType? galleryType,
    FutureOr<void> Function(BuildContext context)? onBackPressed,
    void Function(BuildContext context)? onPageReady,
  }) {
    return DetailPageConfiguration(
      files ?? this.files,
      selectedIndex ?? this.selectedIndex,
      tagPrefix ?? this.tagPrefix,
      mode: mode ?? this.mode,
      isLocalOnlyContext: isLocalOnlyContext ?? this.isLocalOnlyContext,
      showEditAction: showEditAction ?? this.showEditAction,
      showGalleryFilmstrip: showGalleryFilmstrip ?? this.showGalleryFilmstrip,
      galleryType: galleryType ?? this.galleryType,
      onBackPressed: onBackPressed ?? this.onBackPressed,
      onPageReady: onPageReady ?? this.onPageReady,
    );
  }
}

class DetailPage extends StatefulWidget {
  final DetailPageConfiguration config;

  const DetailPage(this.config, {super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _enableFullScreenNotifier = ValueNotifier(false);
  final _isInSharedCollectionNotifier = ValueNotifier(false);
  final _showingThumbnailFallbackNotifier = ValueNotifier<String?>(null);
  final _isZoomedNotifier = ValueNotifier(false);
  final _zoomTransformNotifier = ValueNotifier(ZoomTransform.identity);
  final _bottomControlsAdditionalInsetNotifier = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _bottomControlsAdditionalInsetNotifier.value =
        shouldShowGalleryFileViewerFilmstrip(
          isEnabled: widget.config.showGalleryFilmstrip,
          isMinimalistic: widget.config.mode == DetailPageMode.minimalistic,
          isGuestView: false,
          itemCount: widget.config.files.length,
        )
        ? GalleryFileViewerFilmstripLayout.additionalBottomInset
        : 0;
  }

  @override
  void dispose() {
    _enableFullScreenNotifier.dispose();
    _isInSharedCollectionNotifier.dispose();
    _showingThumbnailFallbackNotifier.dispose();
    _isZoomedNotifier.dispose();
    _zoomTransformNotifier.dispose();
    _bottomControlsAdditionalInsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep InheritedDetailPageState above the rebuilding body so its state
    // survives body rebuilds.
    return InheritedDetailPageState(
      enableFullScreenNotifier: _enableFullScreenNotifier,
      isInSharedCollectionNotifier: _isInSharedCollectionNotifier,
      showingThumbnailFallbackNotifier: _showingThumbnailFallbackNotifier,
      isZoomedNotifier: _isZoomedNotifier,
      zoomTransformNotifier: _zoomTransformNotifier,
      bottomControlsAdditionalInsetNotifier:
          _bottomControlsAdditionalInsetNotifier,
      child: _Body(widget.config),
    );
  }
}

class _Body extends StatefulWidget {
  final DetailPageConfiguration config;

  const _Body(this.config);

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _logger = Logger("DetailPageState");
  bool _shouldDisableScroll = false;
  List<EnteFile>? _files;
  late PageController _pageController;
  final _selectedIndexNotifier = ValueNotifier(0);
  late final FileViewerFilmstripCoordinator _filmstripCoordinator;
  final _inlineTextDetectionController = InlineTextDetectionController();
  bool _isFirstOpened = true;
  bool isGuestView = false;
  bool swipeLocked = false;
  late final StreamSubscription<GuestViewEvent> _guestViewEventSubscription;
  late final StreamSubscription<FileCaptionUpdatedEvent>
  _captionUpdatedSubscription;
  QrCodeDetectionHelper? _qrHelper;
  final Map<String, File> _renderedFiles = {};
  final _playbackSpeed = ValueNotifier<double>(1.0);
  final Map<EnteFile, int> _fileIndexByIdentity = Map.identity();
  final Map<EnteFile, VideoStreamChangeController>
  _videoStreamChangeControllers = Map.identity();
  ValueNotifier<double>? _bottomControlsAdditionalInsetNotifier;

  @override
  void initState() {
    super.initState();
    _files = widget.config.files;
    _rebuildFileIndex();

    final configuredIndex = widget.config.selectedIndex;
    final selectedIndex = _fileAt(configuredIndex) == null
        ? -1
        : configuredIndex;
    _selectedIndexNotifier.value = selectedIndex;
    _pageController = PageController(initialPage: max(0, selectedIndex));
    _filmstripCoordinator = FileViewerFilmstripCoordinator(
      currentIndex: () => _selectedIndexNotifier.value,
      identityAt: _fileAt,
      jumpToPageImmediately: (index) {
        if (!_pageController.hasClients) return false;
        _pageController.jumpToPage(index);
        return true;
      },
      requestPauseCurrentMedia: () {
        final selectedFile = _selectedFile;
        if (selectedFile?.fileType == FileType.video) {
          Bus.instance.fire(PauseVideoEvent(fileTag: selectedFile!.tag));
        }
      },
    );
    _guestViewEventSubscription = Bus.instance.on<GuestViewEvent>().listen((
      event,
    ) {
      if (isGuestView == event.isGuestView &&
          swipeLocked == event.swipeLocked) {
        return;
      }
      setState(() {
        isGuestView = event.isGuestView;
        swipeLocked = event.swipeLocked;
      });
      _syncBottomControlsInset();
    });
    _captionUpdatedSubscription = Bus.instance
        .on<FileCaptionUpdatedEvent>()
        .listen((event) {
          if (event.fileGeneratedID == _selectedFile?.generatedID) {
            setState(() {});
          }
        });
    if (flagService.qrFeatureEnabled &&
        widget.config.mode != DetailPageMode.minimalistic) {
      _qrHelper = QrCodeDetectionHelper();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedFile = _selectedFile;
      if (selectedFile == null) {
        Navigator.maybePop(context).ignore();
        return;
      }
      _updateSharedCollectionState(selectedFile);
      _evaluateQrIfEligible(selectedFile);
      widget.config.onPageReady?.call(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bottomControlsAdditionalInsetNotifier = InheritedDetailPageState.of(
      context,
    ).bottomControlsAdditionalInsetNotifier;
    _syncBottomControlsInset();
  }

  @override
  void dispose() {
    _guestViewEventSubscription.cancel();
    _captionUpdatedSubscription.cancel();
    _filmstripCoordinator.dispose();
    for (final controller in _videoStreamChangeControllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    _selectedIndexNotifier.dispose();
    _qrHelper?.dispose();
    _playbackSpeed.dispose();
    super.dispose();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(systemNavigationBarColor: Color(0x00010000)),
    );

    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  @override
  Widget build(BuildContext context) {
    final selectedFile = _selectedFile;
    if (selectedFile == null) {
      _logger.warning("Closing detail page without a selected file");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.maybePop(context).ignore();
        }
      });
      return const Scaffold(backgroundColor: Colors.black);
    }
    _logger.info(
      "Opening " +
          selectedFile.toString() +
          ". " +
          (_selectedIndexNotifier.value + 1).toString() +
          " / " +
          _files!.length.toString() +
          " files .",
    );
    return PopScope(
      canPop: !isGuestView,
      onPopInvokedWithResult: (didPop, _) async {
        if (isGuestView) {
          final authenticated = await _requestAuthentication();
          if (authenticated) {
            Bus.instance.fire(GuestViewEvent(false, false));
            await localSettings.setOnGuestView(false);
          }
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: ValueListenableBuilder<int?>(
            valueListenable: _filmstripCoordinator.previewIndex,
            builder: (context, previewIndex, child) =>
                AbsorbPointer(absorbing: previewIndex != null, child: child),
            child: ValueListenableBuilder(
              builder: (BuildContext context, int selectedIndex, _) {
                return FileAppBar(
                  _files![selectedIndex],
                  _onFileRemoved,
                  _onEditFileRequested,
                  enableFullScreenNotifier: InheritedDetailPageState.of(
                    context,
                  ).enableFullScreenNotifier,
                  galleryType: widget.config.galleryType,
                  mode: widget.config.mode,
                  showEditAction: widget.config.showEditAction,
                  onBackPressed: widget.config.onBackPressed,
                  playbackSpeed: _playbackSpeed,
                  streamChangeController: _videoStreamChangeControllerFor(
                    _files![selectedIndex],
                  ),
                );
              },
              valueListenable: _selectedIndexNotifier,
            ),
          ),
        ),
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: Center(
          child: Stack(
            children: [
              _buildPageView(),
              // Keep viewer controls above OCR so their real hit boxes, rather
              // than approximated screen insets, decide which gestures they own.
              ValueListenableBuilder(
                valueListenable: _selectedIndexNotifier,
                builder: (BuildContext context, int selectedIndex, _) {
                  if (widget.config.mode == DetailPageMode.minimalistic) {
                    return const SizedBox.shrink();
                  }
                  if (flagService.ocrOverlayEnabled) {
                    return InlineTextDetection(
                      file: _files![selectedIndex],
                      controller: _inlineTextDetectionController,
                      isGuestView: isGuestView,
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              ValueListenableBuilder(
                builder: (BuildContext context, int selectedIndex, _) {
                  final file = _files![selectedIndex];
                  final fullScreenNotifier = InheritedDetailPageState.of(
                    context,
                  ).enableFullScreenNotifier;
                  return _GalleryFileViewerBottomOverlay(
                    file: file,
                    mode: widget.config.mode,
                    isGuestView: isGuestView,
                    hasFilmstrip: _shouldShowFilmstrip,
                    enableFullScreenNotifier: fullScreenNotifier,
                  );
                },
                valueListenable: _selectedIndexNotifier,
              ),
              ValueListenableBuilder(
                valueListenable: _selectedIndexNotifier,
                builder: (BuildContext context, int selectedIndex, _) {
                  return _GallerySocialOverlay(
                    file: _files![selectedIndex],
                    mode: widget.config.mode,
                    isGuestView: isGuestView,
                    hasFilmstrip: _shouldShowFilmstrip,
                  );
                },
              ),
              if (_qrHelper != null)
                ValueListenableBuilder(
                  valueListenable: _selectedIndexNotifier,
                  builder: (BuildContext context, int selectedIndex, _) {
                    if (widget.config.mode == DetailPageMode.minimalistic ||
                        isGuestView ||
                        _files![selectedIndex].isTrash) {
                      return const SizedBox.shrink();
                    }
                    return ValueListenableBuilder(
                      valueListenable: _qrHelper!.qrDetectionsNotifier,
                      builder: (context, result, _) {
                        final file = _files![selectedIndex];
                        return QrCodeHighlightOverlay(
                          detections: result?.forFile(file) ?? const [],
                          file: file,
                        );
                      },
                    );
                  },
                ),
              ValueListenableBuilder(
                valueListenable: _selectedIndexNotifier,
                builder: (BuildContext context, int selectedIndex, _) {
                  if (_files![selectedIndex].isPanorama() == true) {
                    return ValueListenableBuilder(
                      valueListenable: InheritedDetailPageState.of(
                        context,
                      ).enableFullScreenNotifier,
                      builder: (context, value, child) {
                        return IgnorePointer(
                          ignoring: value,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: !value ? 1.0 : 0.0,
                            child: Align(
                              alignment: Alignment.center,
                              child: Tooltip(
                                message: context.strings.panorama,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xAA252525),
                                    fixedSize: const Size(44, 44),
                                  ),
                                  icon: SvgPicture.asset(
                                    "assets/icons/panorama.svg",
                                    width: 24,
                                    height: 24,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  onPressed: () async {
                                    await openPanoramaViewerPage(
                                      _files![selectedIndex],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return const SizedBox();
                },
              ),
              if (_shouldShowFilmstrip)
                GalleryFileViewerFilmstripPreviewLayer(
                  files: _files!,
                  previewIndex: _filmstripCoordinator.previewIndex,
                ),
              if (widget.config.mode != DetailPageMode.minimalistic)
                ValueListenableBuilder<int?>(
                  valueListenable: _filmstripCoordinator.previewIndex,
                  builder: (context, previewIndex, child) => AbsorbPointer(
                    // The toolbar stays visible, but must not act on the old
                    // committed file while another file is being previewed.
                    absorbing: previewIndex != null,
                    child: child,
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: _selectedIndexNotifier,
                    builder: (BuildContext context, int selectedIndex, _) {
                      return FileBottomBar(
                        _files![selectedIndex],
                        onFileRemoved: _onFileRemoved,
                        userID: Configuration.instance.getUserID(),
                        enableFullScreenNotifier: InheritedDetailPageState.of(
                          context,
                        ).enableFullScreenNotifier,
                        isLocalOnlyContext: widget.config.isLocalOnlyContext,
                      );
                    },
                  ),
                ),
              if (_shouldShowFilmstrip)
                ValueListenableBuilder(
                  valueListenable: _selectedIndexNotifier,
                  builder: (BuildContext context, int selectedIndex, _) {
                    return GalleryFileViewerFilmstripOverlay(
                      files: _files!,
                      selectedIndex: selectedIndex,
                      bottomControlsHeight: _galleryBottomBarHeight,
                      findChildIndexCallback: _findChildIndex,
                      enableFullScreenNotifier: InheritedDetailPageState.of(
                        context,
                      ).enableFullScreenNotifier,
                      onEvent: _filmstripCoordinator.handleEvent,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openPanoramaViewerPage(EnteFile file) async {
    final fetchedFile = await getFile(file);
    if (fetchedFile == null) {
      return;
    }
    final fetchedThumbnail = await getThumbnail(file);
    if (!mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) {
              return PanoramaViewerScreen(
                file: fetchedFile,
                thumbnail: fetchedThumbnail,
              );
            },
          ),
        )
        .ignore();
  }

  Widget _buildPageView() {
    return PageView.builder(
      clipBehavior: Clip.none,
      itemBuilder: (context, index) {
        final file = _files![index];
        if (!_filmstripCoordinator.isUserScrollSessionActive) {
          _preloadFiles(index);
        }
        final Widget fileContent = FileWidget(
          file,
          autoPlay: shouldAutoPlay(),
          tagPrefix: widget.config.tagPrefix,
          shouldDisableScroll: (value) {
            if (_selectedFile?.tag != file.tag) return;
            if (_shouldDisableScroll != value) {
              setState(() {
                _logger.info('setState $_shouldDisableScroll to $value');
                _shouldDisableScroll = value;
              });
            }
          },
          playbackCallback: (shouldEnable, reason) {
            Future.delayed(Duration.zero, () {
              if (!context.mounted) return;
              InheritedDetailPageState.of(
                context,
              ).requestFullScreen(shouldEnable: shouldEnable, reason: reason);
            });
          },
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          onFinalImageLoaded: (localFile) {
            _renderedFiles[file.tag] = localFile;
            if (_selectedFile?.tag == file.tag) {
              _evaluateQrIfEligible(file);
            }
          },
          qrDetectionsNotifier: _qrHelper?.qrDetectionsNotifier,
          playbackSpeed: _playbackSpeed,
          itemIndex: index,
          activeItemIndexListenable: _selectedIndexNotifier,
          streamChangeController: _videoStreamChangeControllerFor(file),
          onTextSelectionStart:
              flagService.ocrOverlayEnabled &&
                  widget.config.mode != DetailPageMode.minimalistic &&
                  !file.isLiveOrMotionPhoto
              ? (details) => _inlineTextDetectionController
                    .startTextSelectionAt(file, details.globalPosition)
              : null,
        );
        final page = GestureDetector(
          onTap: () {
            file.fileType != FileType.video
                ? InheritedDetailPageState.of(context).toggleFullScreenByUser()
                : null;
          },
          child: fileContent,
        );
        return KeyedSubtree(
          key: ObjectKey(file),
          child: ValueListenableBuilder(
            valueListenable: _selectedIndexNotifier,
            builder: (context, selectedIndex, _) =>
                HeroMode(enabled: index == selectedIndex, child: page),
          ),
        );
      },
      findChildIndexCallback: _findChildIndex,
      onPageChanged: (index) {
        final file = _fileAt(index);
        if (file == null) {
          return;
        }
        final selectedFileChanged = _selectedFile?.tag != file.tag;
        if (selectedFileChanged) {
          _clearZoomStateForSelectedFileChange();
        }
        if (_selectedIndexNotifier.value == index) {
          if (kDebugMode) {
            debugPrint("onPageChanged called with same index $index");
          }
          // The file count may have changed even when the index did not.
          // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
          _selectedIndexNotifier.notifyListeners();
        } else {
          _selectedIndexNotifier.value = index;
        }
        _filmstripCoordinator.handlePageChanged(index, file);
        if (!_filmstripCoordinator.isUserScrollSessionActive) {
          _runSelectedFileSideEffects(file);
        }
      },
      physics: _shouldDisableScroll || swipeLocked
          ? const NeverScrollableScrollPhysics()
          : const FastScrollPhysics(speedFactor: 4.0),
      controller: _pageController,
      itemCount: _files!.length,
    );
  }

  void _evaluateQrIfEligible(EnteFile file) {
    _qrHelper?.evaluateFile(
      file,
      isGuestView || file.isTrash ? null : _renderedFiles[file.tag],
    );
  }

  bool shouldAutoPlay() {
    if (_isFirstOpened) {
      _isFirstOpened = false;
      return true;
    }
    return false;
  }

  void _preloadFiles(int index) {
    if (index > 0) {
      preloadThumbnail(_files![index - 1]);
      preloadFile(_files![index - 1]);
    }
    if (index < _files!.length - 1) {
      preloadThumbnail(_files![index + 1]);
      preloadFile(_files![index + 1]);
    }
  }

  void _runSelectedFileSideEffects(EnteFile file) {
    Bus.instance.fire(GuestViewEvent(isGuestView, swipeLocked));
    _updateSharedCollectionState(file);
    _evaluateQrIfEligible(file);
  }

  Future<void> _onFileRemoved(EnteFile file) async {
    if (!mounted || _files == null) return;
    _filmstripCoordinator.reset();
    final files = _files!;
    final removedIndex = _indexOfFile(file);
    if (removedIndex < 0) {
      _logger.warning("Ignoring removal for a file outside the viewer");
      return;
    }
    final totalFiles = files.length;
    if (totalFiles == 1) {
      Navigator.of(context).pop();
      return;
    }

    final oldSelectedIndex = _selectedIndexNotifier.value;
    final nextSelectedIndex = removedIndex < oldSelectedIndex
        ? oldSelectedIndex - 1
        : removedIndex == oldSelectedIndex
        ? min(oldSelectedIndex, totalFiles - 2)
        : oldSelectedIndex;
    setState(() {
      _shouldDisableScroll = false;
      final removedFile = files.removeAt(removedIndex);
      final removedController = _videoStreamChangeControllers.remove(
        removedFile,
      );
      if (removedController != null) {
        // The outgoing page and app bar detach from this controller while the
        // removal frame is built. Dispose it only after those widgets unmount.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          removedController.dispose();
        });
      }
      _rebuildFileIndex();
      if (_selectedIndexNotifier.value == nextSelectedIndex) {
        // The item at this index may have changed even though the index did not.
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        _selectedIndexNotifier.notifyListeners();
      } else {
        _selectedIndexNotifier.value = nextSelectedIndex;
      }
    });
    _clearZoomNotifiers();
    _syncBottomControlsInset();
    final selectedFile = _selectedFile;
    if (selectedFile != null) {
      unawaited(_updateSharedCollectionState(selectedFile));
      _evaluateQrIfEligible(selectedFile);
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_pageController.hasClients) return;
    final currentPageIndex = _pageController.page?.round() ?? oldSelectedIndex;
    if (currentPageIndex != nextSelectedIndex) {
      await _pageController.animateToPage(
        nextSelectedIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  void _clearZoomStateForSelectedFileChange() {
    if (_shouldDisableScroll) {
      setState(() => _shouldDisableScroll = false);
    }
    _clearZoomNotifiers();
  }

  void _clearZoomNotifiers() {
    final detailState = InheritedDetailPageState.maybeOf(context);
    if (detailState == null) return;
    if (detailState.isZoomedNotifier.value) {
      detailState.isZoomedNotifier.value = false;
    }
    if (detailState.zoomTransformNotifier.value != ZoomTransform.identity) {
      detailState.zoomTransformNotifier.value = ZoomTransform.identity;
    }
  }

  Future<void> _onEditFileRequested(EnteFile file) async {
    if (file.uploadedFileID != null &&
        file.ownerID != Configuration.instance.getUserID()) {
      _logger.severe(
        "Attempt to edit unowned file",
        UnauthorizedEditError(),
        StackTrace.current,
      );
      // ignore: unawaited_futures
      showErrorDialog(
        context,
        context.strings.sorry,
        context.strings.weDontSupportEditingPhotosAndAlbumsThatYouDont,
      );
      return;
    }
    final dialog = createProgressDialog(context, context.strings.pleaseWait);
    await dialog.show();

    try {
      final ioFile = await getFile(file);
      if (ioFile == null) {
        if (!mounted) return;
        showShortToast(context, context.strings.failedToFetchOriginalForEdit);
        await dialog.hide();
        return;
      }
      if (file.fileType == FileType.video) {
        await dialog.hide();
        if (!mounted) return;
        replacePage(
          context,
          VideoEditorPage(
            file: file,
            ioFile: ioFile,
            detailPageConfig: widget.config.copyWith(
              files: _files,
              selectedIndex: _selectedIndexNotifier.value,
            ),
          ),
        );
        return;
      }
      final imageProvider = ExtendedFileImageProvider(
        ioFile,
        cacheRawData: true,
      );
      if (!mounted) return;
      await precacheImage(imageProvider, context);
      await dialog.hide();
      if (!mounted) return;
      replacePage(
        context,
        ImageEditorPage(
          originalFile: file,
          file: ioFile,
          detailPageConfig: widget.config.copyWith(
            files: _files,
            selectedIndex: _selectedIndexNotifier.value,
          ),
        ),
      );
    } catch (e) {
      await dialog.hide();
      _logger.warning("Failed to initiate edit", e);
    }
  }

  Future<bool> _requestAuthentication() async {
    return await LocalAuthenticationService.instance.requestLocalAuthentication(
      context,
      "Please authenticate to view more photos and videos.",
    );
  }

  Future<void> _updateSharedCollectionState(EnteFile file) async {
    final fileID = file.uploadedFileID;
    final notifier = InheritedDetailPageState.maybeOf(
      context,
    )?.isInSharedCollectionNotifier;

    if (notifier == null) return;

    if (fileID == null) {
      notifier.value = false;
      return;
    }

    final isShared = await CollectionsService.instance.isFileInSharedCollection(
      fileID,
    );

    // Ignore results for a file the user swiped away from while awaiting.
    if (_selectedFile?.uploadedFileID == fileID) {
      notifier.value = isShared;
    }
  }

  EnteFile? get _selectedFile => _fileAt(_selectedIndexNotifier.value);

  bool get _shouldShowFilmstrip => shouldShowGalleryFileViewerFilmstrip(
    isEnabled: widget.config.showGalleryFilmstrip,
    isMinimalistic: widget.config.mode == DetailPageMode.minimalistic,
    isGuestView: isGuestView,
    itemCount: _files?.length ?? 0,
  );

  void _syncBottomControlsInset() {
    final notifier = _bottomControlsAdditionalInsetNotifier;
    if (notifier == null) return;
    if (!_shouldShowFilmstrip) _filmstripCoordinator.reset();
    final inset = _shouldShowFilmstrip
        ? GalleryFileViewerFilmstripLayout.additionalBottomInset
        : 0.0;
    notifier.value = inset;
  }

  EnteFile? _fileAt(int index) {
    final files = _files;
    if (files == null || index < 0 || index >= files.length) {
      return null;
    }
    return files[index];
  }

  int _indexOfFile(EnteFile file) {
    final files = _files;
    if (files == null) return -1;
    final identityIndex = _fileIndexByIdentity[file];
    if (identityIndex != null) return identityIndex;

    final identifier = detailPageFileIdentifier(file);
    if (identifier == null) return -1;
    return files.indexWhere(
      (item) => detailPageFileIdentifier(item) == identifier,
    );
  }

  int? _findChildIndex(Key key) {
    if (key is! ObjectKey) return null;
    final value = key.value;
    return value is EnteFile ? _fileIndexByIdentity[value] : null;
  }

  VideoStreamChangeController? _videoStreamChangeControllerFor(EnteFile file) {
    if (file.fileType != FileType.video) return null;
    return _videoStreamChangeControllers.putIfAbsent(
      file,
      VideoStreamChangeController.new,
    );
  }

  void _rebuildFileIndex() {
    _fileIndexByIdentity.clear();
    final files = _files;
    if (files == null) return;
    for (var index = 0; index < files.length; index++) {
      _fileIndexByIdentity[files[index]] = index;
    }
  }
}

class _GalleryFileViewerBottomOverlay extends StatelessWidget {
  final EnteFile file;
  final DetailPageMode mode;
  final bool isGuestView;
  final bool hasFilmstrip;
  final ValueListenable<bool> enableFullScreenNotifier;

  const _GalleryFileViewerBottomOverlay({
    required this.file,
    required this.mode,
    required this.isGuestView,
    required this.hasFilmstrip,
    required this.enableFullScreenNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = file.fileType == FileType.video;
    final caption = file.caption;
    final captionText = caption == null || caption.isEmpty ? null : caption;
    final hasBottomBar = mode != DetailPageMode.minimalistic && !isGuestView;
    if (captionText == null && (isVideo || !hasBottomBar)) {
      return const SizedBox.shrink();
    }

    final safePadding = MediaQuery.paddingOf(context);
    final captionStyle = getEnteTextTheme(
      context,
    ).mini.copyWith(color: textBaseDark.withValues(alpha: 0.8));
    final filmstripInset = hasFilmstrip
        ? GalleryFileViewerFilmstripLayout.additionalBottomInset
        : 0.0;
    return ValueListenableBuilder<bool>(
      valueListenable: enableFullScreenNotifier,
      builder: (context, isFullScreen, _) {
        return IgnorePointer(
          ignoring: isFullScreen,
          child: AnimatedOpacity(
            opacity: isFullScreen ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: Stack(
              children: [
                if (!isVideo)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      child: SizedBox(
                        width: double.infinity,
                        height:
                            safePadding.bottom +
                            _galleryBottomBarHeight +
                            filmstripInset +
                            (captionText == null
                                ? 0
                                : _galleryCaptionGap +
                                      _galleryCaptionLineHeight +
                                      _galleryCaptionScrimTopPadding),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.6),
                                Colors.black.withValues(alpha: 0.72),
                              ],
                              stops: const [0, 0.8, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (captionText != null)
                  Positioned(
                    left: safePadding.left + 16,
                    right: safePadding.right + 16,
                    bottom:
                        safePadding.bottom +
                        (isVideo
                            ? kVideoProgressBottomInset +
                                  kVideoProgressHeight +
                                  filmstripInset +
                                  kVideoCaptionGap
                            : _galleryBottomBarHeight +
                                  filmstripInset +
                                  _galleryCaptionGap),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => showDetailsSheet(context, file),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('"', style: captionStyle),
                            Flexible(
                              child: Text(
                                captionText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: captionStyle,
                              ),
                            ),
                            Text('"', style: captionStyle),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// This widget returns Positioned, so its parent must be a Stack.
class _GallerySocialOverlay extends StatelessWidget {
  final EnteFile file;
  final DetailPageMode mode;
  final bool isGuestView;
  final bool hasFilmstrip;

  const _GallerySocialOverlay({
    required this.file,
    required this.mode,
    required this.isGuestView,
    required this.hasFilmstrip,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == DetailPageMode.minimalistic || isGuestView || file.isTrash) {
      return const SizedBox.shrink();
    }

    final padding = MediaQuery.paddingOf(context);
    final fullScreenNotifier = InheritedDetailPageState.of(
      context,
    ).enableFullScreenNotifier;
    return Positioned(
      right: padding.right + _socialRightInset,
      bottom:
          padding.bottom +
          _socialBottomBarClearance -
          (file.fileType == FileType.video ? _videoStreamControlHeight : 0) +
          (hasFilmstrip
              ? GalleryFileViewerFilmstripLayout.additionalBottomInset
              : 0),
      child: ValueListenableBuilder<bool>(
        valueListenable: fullScreenNotifier,
        builder: (context, isFullScreen, child) => IgnorePointer(
          ignoring: isFullScreen,
          child: AnimatedOpacity(
            opacity: isFullScreen ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: child,
          ),
        ),
        child: FileSocialOverlay(
          file: file,
          currentUserID: Configuration.instance.getUserID(),
          openingCollectionID: file.collectionID,
        ),
      ),
    );
  }
}
