import 'dart:async';
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:flutter_animate/flutter_animate.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/event.dart';
import 'package:photos/events/files_updated_event.dart';
import "package:photos/events/homepage_swipe_to_select_in_progress_event.dart";
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/events/tab_changed_event.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/models/gallery_type.dart";
import 'package:photos/models/selected_files.dart';
import "package:photos/service_locator.dart" show localSettings;
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/component/sectioned_sliver_list.dart";
import 'package:photos/ui/viewer/gallery/empty_state.dart';
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/scrollbar/custom_scroll_bar.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_context_state.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/swipe_selection_wrapper.dart";
import "package:photos/ui/viewer/gallery/swipe_to_select_helper.dart";
import "package:photos/utils/hierarchical_search_util.dart";
import "package:photos/utils/misc_util.dart";
import "package:photos/utils/widget_util.dart";

typedef GalleryLoader =
    Future<FileLoadResult> Function(
      int creationStartTime,
      int creationEndTime, {
      int? limit,
      bool? asc,
    });

typedef SortAscFn = bool Function();

typedef NewLocalFilesResolver =
    Future<List<EnteFile>?> Function(LocalPhotosAddedEvent event);

class Gallery extends StatefulWidget {
  final GalleryLoader asyncLoader;
  final List<EnteFile>? initialFiles;
  final Stream<FilesUpdatedEvent>? reloadEvent;
  final List<Stream<Event>>? forceReloadEvents;
  final Set<EventType> removalEventTypes;
  final SelectedFiles? selectedFiles;
  final String tagPrefix;
  final GalleryAppBarConfig? appBar;
  final Widget? header;
  final Widget? footer;
  final Widget emptyState;
  final String? albumName;
  final bool enableFileGrouping;
  final Widget loadingWidget;
  final bool disableScroll;
  final Duration reloadDebounceTime;
  final Duration reloadDebounceExecutionInterval;
  final Duration priorityReloadDebounceTime;
  final GalleryType? galleryType;
  final bool showGallerySettingsCTA;

  // Return null to force a full reload.
  final NewLocalFilesResolver? newLocalFilesResolver;

  // Single-selection mode also selects on the first tap.
  final bool limitSelectionToOne;

  final bool addHeaderOrFooterEmptyState;

  // Enables tap-to-select; it does not indicate whether files are selected.
  final bool inSelectionMode;
  final bool showSelectAll;

  final SortAscFn? sortAsyncFn;

  final GroupType? groupType;
  final bool disablePinnedGroupHeader;
  final bool disableVerticalPaddingForScrollbar;

  final EnteFile? fileToJumpTo;

  const Gallery({
    required this.asyncLoader,
    required this.tagPrefix,
    this.appBar,
    this.selectedFiles,
    this.initialFiles,
    this.reloadEvent,
    this.forceReloadEvents,
    this.removalEventTypes = const {},
    this.header,
    this.footer = const SizedBox(height: 212),
    this.addHeaderOrFooterEmptyState = true,
    this.emptyState = const EmptyState(),
    this.albumName = '',
    this.groupType,
    this.enableFileGrouping = true,
    this.loadingWidget = const EnteLoadingWidget(),
    this.disableScroll = false,
    this.limitSelectionToOne = false,
    this.inSelectionMode = false,
    this.sortAsyncFn,
    this.showSelectAll = true,
    this.reloadDebounceTime = const Duration(milliseconds: 500),
    this.reloadDebounceExecutionInterval = const Duration(seconds: 2),
    this.priorityReloadDebounceTime = const Duration(milliseconds: 200),
    this.disablePinnedGroupHeader = false,
    this.galleryType,
    this.disableVerticalPaddingForScrollbar = false,
    this.showGallerySettingsCTA = false,
    this.fileToJumpTo,
    this.newLocalFilesResolver,
    super.key,
  });

  @override
  State<Gallery> createState() {
    return GalleryState();
  }
}

class GalleryState extends State<Gallery> {
  static const int kInitialLoadLimit = 100;
  static final RegExp _automationIdentifierUnsafeChars = RegExp(
    r'[^A-Za-z0-9_.-]',
  );
  late final Debouncer _debouncer;
  late final Debouncer _priorityDebouncer;
  double? groupHeaderExtent;

  late Logger _logger;
  bool _hasLoadedFiles = false;
  bool _allFilesLoaded = false;
  bool _completedJumpToDate = false;
  StreamSubscription<FilesUpdatedEvent>? _reloadEventSubscription;
  StreamSubscription<TabDoubleTapEvent>? _tabDoubleTapEvent;
  final _forceReloadEventSubscriptions = <StreamSubscription<Event>>[];
  late String _logTag;
  bool _sortOrderAsc = false;
  int _activeFileLoads = 0;
  List<EnteFile> _allGalleryFiles = [];
  final _scrollController = ScrollController();
  final _headerKey = GlobalKey();
  final _headerHeightNotifier = ValueNotifier<double?>(null);
  final miscUtil = MiscUtil();
  final scrollBarInUseNotifier = ValueNotifier<bool>(false);
  late GroupType _groupType;
  final scrollbarBottomPaddingNotifier = ValueNotifier<double>(0);
  GalleryGroups? galleryGroups;
  List<EnteFile> _allFilesWithDummies = [];
  SwipeToSelectHelper? _swipeHelper;
  final _swipeActiveNotifier = ValueNotifier<bool>(false);
  InheritedSearchFilterData? _inheritedSearchFilterData;
  InheritedGalleryBoundaries? _boundariesProvider;
  late String _automationScrollIdentifier;

  @override
  void initState() {
    super.initState();
    _automationScrollIdentifier = _buildAutomationScrollIdentifier(
      widget.tagPrefix,
    );
    // Keep the logger name from ending in a dot.
    _logTag =
        "Gallery_${widget.tagPrefix}${kDebugMode ? "_" + widget.albumName! : ""}_x";
    _logger = Logger(_logTag);
    _logger.info("init Gallery");

    if (widget.limitSelectionToOne) {
      assert(widget.showSelectAll == false);
    }

    _setGroupType();
    _debouncer = Debouncer(
      widget.reloadDebounceTime,
      executionInterval: widget.reloadDebounceExecutionInterval,
      leading: true,
    );
    _priorityDebouncer = Debouncer(
      widget.priorityReloadDebounceTime,
      leading: true,
    );
    _sortOrderAsc = widget.sortAsyncFn != null ? widget.sortAsyncFn!() : false;
    if (widget.reloadEvent != null) {
      _reloadEventSubscription = widget.reloadEvent!.listen((event) async {
        bool shouldReloadFromDB = true;
        if (event.source == 'uploadCompleted') {
          shouldReloadFromDB = _shouldReloadOnUploadCompleted(event);
        } else if (event.source == 'fileMissingLocal') {
          shouldReloadFromDB = _shouldReloadOnFileMissingLocal(event);
        }
        if (!shouldReloadFromDB) {
          final bool hasCalledSetState = _onFilesLoaded(_allGalleryFiles);
          _logger.info(
            'Skip softRefresh from DB on ${event.reason}, processed updated in memory with setStateReload $hasCalledSetState',
          );
          return;
        }

        if (event is LocalPhotosAddedEvent &&
            await _tryAddNewLocalFiles(event)) {
          return;
        }

        final isPriorityEvent =
            event is LocalPhotosUpdatedEvent &&
            event.hasRecentNewLocalDiscovery;

        final targetDebouncer = isPriorityEvent
            ? _priorityDebouncer
            : _debouncer;

        targetDebouncer.run(() async {
          _logger.info(
            "${isPriorityEvent ? 'Priority' : 'Soft'} refresh on ${event.reason}",
          );
          final result = await _loadFiles();
          final bool hasTriggeredSetState = _onFilesLoaded(result.files);
          if (hasTriggeredSetState && kDebugMode) {
            _logger.info("Reloaded gallery on ${event.reason}");
          }
          if (!hasTriggeredSetState && mounted) {
            _updateGalleryGroups();
          }
        });
      });
    }
    _tabDoubleTapEvent = Bus.instance.on<TabDoubleTapEvent>().listen((
      event,
    ) async {
      // todo: Assign ID to Gallery and fire generic event with ID &
      //  target index/date
      if (mounted && event.selectedIndex == 0) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutExpo,
        );
      }
    });
    if (widget.forceReloadEvents != null) {
      for (final event in widget.forceReloadEvents!) {
        _forceReloadEventSubscriptions.add(
          event.listen((event) async {
            _debouncer.run(() async {
              _logger.info("Force refresh all files on ${event.reason}");
              _sortOrderAsc = widget.sortAsyncFn != null
                  ? widget.sortAsyncFn!()
                  : false;
              _setGroupType();
              final result = await _loadFiles();
              _setFilesAndReload(result.files);
            });
          }),
        );
      }
    }
    if (widget.initialFiles != null && !_sortOrderAsc) {
      _onFilesLoaded(widget.initialFiles!);
    }

    _loadFiles(limit: kInitialLoadLimit).then((result) async {
      _setFilesAndReload(result.files);
      if (result.hasMore) {
        final result = await _loadFiles();
        _setFilesAndReload(result.files);
        _allFilesLoaded = true;
      } else {
        _allFilesLoaded = true;
      }
    });

    if (_groupType.showGroupHeader()) {
      getIntrinsicSizeOfWidget(
        GroupHeaderWidget(
          title: "Dummy title",
          gridSize: localSettings.getPhotoGridSize(),
          filesInGroup: const [],
          selectedFiles: null,
          showSelectAll: false,
        ),
        context,
      ).then((size) {
        if (!mounted) return;
        setState(() {
          groupHeaderExtent = size.height;
          _updateGalleryGroups(callSetState: false);
        });
      });
    } else {
      groupHeaderExtent = GalleryGroups.spacing;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateGalleryGroups();
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _selectedFilesListener();
      try {
        final headerRenderBox = await miscUtil
            .getNonNullValueWithRetry(
              () => _headerKey.currentContext?.findRenderObject(),
              retryInterval: const Duration(milliseconds: 750),
              id: "headerRenderBox",
            )
            .then((value) => value as RenderBox);

        _headerHeightNotifier.value = headerRenderBox.size.height;
      } catch (e, s) {
        _logger.warning("Error getting renderBox offset", e, s);
      }
      setState(() {});
    });

    widget.selectedFiles?.addListener(_selectedFilesListener);

    if (widget.galleryType == GalleryType.homepage) {
      _swipeActiveNotifier.addListener(() {
        Bus.instance.fire(
          HomepageSwipeToSelectInProgressEvent(
            isInProgress: _swipeActiveNotifier.value,
          ),
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant Gallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tagPrefix != widget.tagPrefix) {
      _automationScrollIdentifier = _buildAutomationScrollIdentifier(
        widget.tagPrefix,
      );
    }
    if (oldWidget.groupType != widget.groupType) {
      _setGroupType();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(context);
    _boundariesProvider = GalleryBoundariesProvider.of(context);
  }

  void _updateGalleryGroups({bool callSetState = true}) {
    if (groupHeaderExtent == null) return;
    final groups = GalleryGroups(
      allFiles: _allGalleryFiles,
      groupType: _groupType,
      sortOrderAsc: _sortOrderAsc,
      widthAvailable: MediaQuery.sizeOf(context).width,
      selectedFiles: widget.selectedFiles,
      tagPrefix: widget.tagPrefix,
      groupHeaderExtent: groupHeaderExtent!,
      showSelectAll: widget.showSelectAll,
      limitSelectionToOne: widget.limitSelectionToOne,
      showGallerySettingsCTA: widget.showGallerySettingsCTA,
    );
    galleryGroups = groups;

    // Keep dummy cells in the swipe index so it matches the rendered grid.
    _allFilesWithDummies = groups.allFilesWithDummies;
    _updateSwipeHelper();

    if (callSetState) {
      setState(() {});
    }
  }

  void _selectedFilesListener() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final extra = widget.galleryType == GalleryType.homepage ? 76.0 : 0.0;
    widget.selectedFiles?.files.isEmpty ?? true
        ? scrollbarBottomPaddingNotifier.value = bottomInset + extra
        : scrollbarBottomPaddingNotifier.value =
              FileSelectionOverlayBar.roughHeight + bottomInset;
  }

  void _setGroupType() {
    if (!widget.enableFileGrouping) {
      _groupType = GroupType.none;
    } else if (widget.groupType != null) {
      _groupType = widget.groupType!;
    } else {
      _groupType = localSettings.getGalleryGroupType();
    }
  }

  void _setFilesAndReload(List<EnteFile> files) {
    final hasReloaded = _onFilesLoaded(files);
    if (!hasReloaded && mounted) {
      _updateGalleryGroups();
    }
  }

  bool _shouldReloadOnUploadCompleted(FilesUpdatedEvent event) {
    bool shouldReloadFromDB = true;
    if (event.source == 'uploadCompleted') {
      final Map<int, EnteFile> genIDToUploadedFiles = {};
      for (int i = 0; i < event.updatedFiles.length; i++) {
        if (event.updatedFiles[i].generatedID == null) {
          return true;
        }
        genIDToUploadedFiles[event.updatedFiles[i].generatedID!] =
            event.updatedFiles[i];
      }
      for (int i = 0; i < _allGalleryFiles.length; i++) {
        final file = _allGalleryFiles[i];
        if (file.generatedID == null) {
          continue;
        }
        final updateFile = genIDToUploadedFiles[file.generatedID!];
        if (updateFile != null &&
            updateFile.localID == file.localID &&
            areFromSameDay(
              updateFile.creationTime ?? 0,
              file.creationTime ?? 0,
            )) {
          final file = _allGalleryFiles[i];
          if (widget.selectedFiles != null) {
            widget.selectedFiles!.mutateFile(file, () {
              file.applyUploadedData(updateFile);
            });
          } else {
            file.applyUploadedData(updateFile);
          }
          genIDToUploadedFiles.remove(file.generatedID!);
        }
      }
      shouldReloadFromDB = genIDToUploadedFiles.isNotEmpty;
    }
    return shouldReloadFromDB;
  }

  bool _shouldReloadOnFileMissingLocal(FilesUpdatedEvent event) {
    bool shouldReloadFromDB = true;
    if (event.source != 'fileMissingLocal' ||
        event.type != EventType.deletedFromEverywhere) {
      _logger.warning(
        "Invalid event source or type for fileMissingLocal: ${event.source} ${event.type}",
      );
      return true;
    }
    final Map<int, EnteFile> genIDToUploadedFiles = {};
    for (int i = 0; i < event.updatedFiles.length; i++) {
      if (event.updatedFiles[i].generatedID == null ||
          event.updatedFiles[i].localID == null ||
          event.updatedFiles[i].isUploaded) {
        _logger.warning(
          "Invalid file in updatedFiles: ${event.updatedFiles[i].localID} ${event.updatedFiles[i].generatedID} ${event.updatedFiles[i].isUploaded}",
        );
        return shouldReloadFromDB;
      }
      genIDToUploadedFiles[event.updatedFiles[i].generatedID!] =
          event.updatedFiles[i];
    }
    final List<EnteFile> newAllGalleryFiles = [];
    for (int i = 0; i < _allGalleryFiles.length; i++) {
      final file = _allGalleryFiles[i];
      if (file.generatedID == null) {
        newAllGalleryFiles.add(file);
        continue;
      }
      final updateFile = genIDToUploadedFiles[file.generatedID!];
      if (updateFile != null &&
          areFromSameDay(
            updateFile.creationTime ?? 0,
            file.creationTime ?? 0,
          )) {
        genIDToUploadedFiles.remove(file.generatedID!);
      } else {
        newAllGalleryFiles.add(file);
      }
    }
    shouldReloadFromDB = genIDToUploadedFiles.isNotEmpty;
    if (!shouldReloadFromDB) {
      _allGalleryFiles = newAllGalleryFiles;
    }
    return shouldReloadFromDB;
  }

  bool _onFilesLoaded(List<EnteFile> files) {
    _allGalleryFiles = files;
    _hasLoadedFiles = true;
    return false;
  }

  Future<bool> _tryAddNewLocalFiles(LocalPhotosAddedEvent event) async {
    final resolver = widget.newLocalFilesResolver;
    if (resolver == null || !_allFilesLoaded || _activeFileLoads > 0) {
      return false;
    }

    List<EnteFile>? resolvedFiles;
    try {
      resolvedFiles = await resolver(event);
    } catch (e, s) {
      _logger.warning('Failed to resolve new local files', e, s);
      return false;
    }
    if (resolvedFiles == null) return false;
    if (!mounted) return true;
    if (_activeFileLoads > 0) return false;

    final visibleLocalIDs = _allGalleryFiles
        .map((file) => file.localID)
        .nonNulls
        .toSet();
    final filesToAdd =
        resolvedFiles
            .where(
              (file) =>
                  file.localID != null && visibleLocalIDs.add(file.localID!),
            )
            .toList()
          ..sort(_compareGalleryFiles);
    if (filesToAdd.isNotEmpty) {
      _setFilesAndReload(_mergeGalleryFiles(filesToAdd));
    }
    _logger.info('Added ${filesToAdd.length} new local files in memory');
    return true;
  }

  List<EnteFile> _mergeGalleryFiles(List<EnteFile> filesToAdd) {
    final merged = <EnteFile>[];
    var currentIndex = 0;
    var addedIndex = 0;
    while (currentIndex < _allGalleryFiles.length &&
        addedIndex < filesToAdd.length) {
      if (_compareGalleryFiles(
            filesToAdd[addedIndex],
            _allGalleryFiles[currentIndex],
          ) <
          0) {
        merged.add(filesToAdd[addedIndex++]);
      } else {
        merged.add(_allGalleryFiles[currentIndex++]);
      }
    }
    merged.addAll(_allGalleryFiles.skip(currentIndex));
    merged.addAll(filesToAdd.skip(addedIndex));
    return merged;
  }

  int _compareGalleryFiles(EnteFile first, EnteFile second) {
    var result = (first.creationTime ?? 0).compareTo(second.creationTime ?? 0);
    if (result == 0) {
      result = (first.modificationTime ?? 0).compareTo(
        second.modificationTime ?? 0,
      );
    }
    return _sortOrderAsc ? result : -result;
  }

  void _updateSwipeHelper() {
    if (widget.selectedFiles != null && _allFilesWithDummies.isNotEmpty) {
      _swipeHelper?.dispose();
      _swipeHelper = SwipeToSelectHelper(
        allFiles: _allFilesWithDummies,
        selectedFiles: widget.selectedFiles!,
      );
    }
  }

  Future<FileLoadResult> _loadFiles({int? limit}) async {
    _logger.info("Loading ${limit ?? "all"} files");
    _activeFileLoads++;
    try {
      final startTime = DateTime.now().microsecondsSinceEpoch;
      final result = await widget.asyncLoader(
        galleryLoadStartTime,
        galleryLoadEndTime,
        limit: limit,
        asc: _sortOrderAsc,
      );
      final endTime = DateTime.now().microsecondsSinceEpoch;
      final duration = Duration(microseconds: endTime - startTime);
      _logger.info(
        "Time taken to load " +
            result.files.length.toString() +
            " files :" +
            duration.inMilliseconds.toString() +
            "ms",
      );

      if (!result.hasMore) {
        if (!mounted) {
          return result;
        }
        final inheritedSearchFilterData = _inheritedSearchFilterData;
        final searchFilterDataProvider =
            inheritedSearchFilterData?.isHierarchicalSearchable == true
            ? inheritedSearchFilterData!.searchFilterDataProvider
            : null;
        if (searchFilterDataProvider != null &&
            !searchFilterDataProvider.isSearchingNotifier.value) {
          unawaited(
            curateFilters(searchFilterDataProvider, result.files, context),
          );
        }
      }

      return result;
    } catch (e, s) {
      _logger.severe("failed to load files", e, s);
      rethrow;
    } finally {
      _activeFileLoads--;
    }
  }

  @override
  void dispose() {
    _boundariesProvider?.setScrollController(null);

    _reloadEventSubscription?.cancel();
    _tabDoubleTapEvent?.cancel();
    for (final subscription in _forceReloadEventSubscriptions) {
      subscription.cancel();
    }
    _debouncer.cancelDebounceTimer();
    _priorityDebouncer.cancelDebounceTimer();
    _scrollController.dispose();
    scrollBarInUseNotifier.dispose();
    _headerHeightNotifier.dispose();
    widget.selectedFiles?.removeListener(_selectedFilesListener);
    scrollbarBottomPaddingNotifier.dispose();
    _swipeHelper?.dispose();
    _swipeActiveNotifier.dispose();
    super.dispose();
  }

  double get _headerHeight {
    final cachedHeight = _headerHeightNotifier.value;
    if (cachedHeight != null) {
      return cachedHeight;
    }
    final renderBox = _headerKey.currentContext?.findRenderObject();
    return renderBox is RenderBox && renderBox.hasSize
        ? renderBox.size.height
        : 0;
  }

  double _scrollOffsetForSectionOffset(
    double sectionOffset,
    double appBarCollapseExtent,
  ) {
    return sectionOffset + appBarCollapseExtent + _headerHeight;
  }

  ScrollPhysics get _scrollPhysics => widget.disableScroll
      ? const NeverScrollableScrollPhysics()
      : const BouncingScrollPhysics();

  static String _buildAutomationScrollIdentifier(String tagPrefix) {
    final safeTagPrefix = tagPrefix.replaceAll(
      _automationIdentifierUnsafeChars,
      '_',
    );
    return "ente.photos.gallery.$safeTagPrefix.scroll";
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building Gallery  ${widget.tagPrefix}");
    final appBarGeometry = widget.appBar?.resolveGeometry(context);
    final appBarPinnedHeight = appBarGeometry?.minExtent ?? 0;
    final appBarCollapseExtent = appBarGeometry?.collapseExtent ?? 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _boundariesProvider?.setScrollController(_scrollController);
      }
    });

    if (widget.fileToJumpTo != null &&
        !_completedJumpToDate &&
        _allFilesLoaded &&
        groupHeaderExtent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          final offset = galleryGroups?.getOffsetOfGroupContainingFile(
            widget.fileToJumpTo!,
          );
          if (offset != null) {
            final scrollOffset = _scrollOffsetForSectionOffset(
              offset,
              appBarCollapseExtent,
            );
            _logger.info("Jumping to date at offset: $scrollOffset");
            _scrollController.jumpTo(scrollOffset - 50);
            await Future.delayed(16.milliseconds);
            await _scrollController.animateTo(
              scrollOffset,
              duration: 300.milliseconds,
              curve: Curves.easeOutQuint,
            );
            _completedJumpToDate = true;
          } else {
            _logger.warning(
              "Could not find offset for file to jump to: ${widget.fileToJumpTo!.tag}",
            );
          }
        }
      });
    }

    final widthAvailable = MediaQuery.sizeOf(context).width;
    final shouldEnableSwipeSelection = widget.limitSelectionToOne == false;

    if (groupHeaderExtent == null) {
      final photoGridSize = localSettings.getPhotoGridSize();
      final tileHeight =
          (widthAvailable - (photoGridSize - 1) * GalleryGroups.spacing) /
          photoGridSize;
      final placeholder =
          widget.initialFiles != null && widget.initialFiles!.isNotEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                widget.header ?? const SizedBox.shrink(),
                GroupHeaderWidget(
                  title: "",
                  gridSize: photoGridSize,
                  filesInGroup: const [],
                  selectedFiles: null,
                  showSelectAll: false,
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: tileHeight,
                    width: tileHeight,
                    child: GalleryFileWidget(
                      file: widget.initialFiles!.first,
                      selectedFiles: null,
                      limitSelectionToOne: false,
                      tag: widget.tagPrefix,
                      photoGridSize: photoGridSize,
                      currentUserID: null,
                    ),
                  ),
                ),
              ],
            )
          : const SizedBox.shrink();
      return _GalleryAppBarScrollBody(
        appBar: widget.appBar,
        physics: _scrollPhysics,
        child: placeholder,
      );
    }

    GalleryFilesState.of(context).setGalleryFiles = _allGalleryFiles;
    if (!_hasLoadedFiles) {
      return _GalleryAppBarScrollBody(
        appBar: widget.appBar,
        physics: _scrollPhysics,
        child: widget.loadingWidget,
      );
    }

    if (galleryGroups == null) {
      _updateGalleryGroups(callSetState: false);
    }
    final groups = galleryGroups;
    if (groups == null) {
      return _GalleryAppBarScrollBody(
        appBar: widget.appBar,
        physics: _scrollPhysics,
        child: widget.loadingWidget,
      );
    }

    if (groups.widthAvailable != widthAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateGalleryGroups();
        }
      });
    }
    if (appBarPinnedHeight > 0 &&
        (!groups.groupType.showGroupHeader() ||
            widget.disablePinnedGroupHeader)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _boundariesProvider?.setTopBoundary(appBarPinnedHeight);
        }
      });
    }

    return SwipeSelectionWrapper(
      isEnabled: shouldEnableSwipeSelection,
      swipeHelper: _swipeHelper,
      selectedFiles: widget.selectedFiles,
      swipeActiveNotifier: _swipeActiveNotifier,
      scrollController: _scrollController,
      child: GalleryContextState(
        sortOrderAsc: _sortOrderAsc,
        inSelectionMode: widget.inSelectionMode,
        type: _groupType,
        galleryType: widget.galleryType,
        child: _allGalleryFiles.isEmpty
            ? _GalleryAppBarScrollBody(
                appBar: widget.appBar,
                physics: _scrollPhysics,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.addHeaderOrFooterEmptyState)
                      widget.header ?? const SizedBox.shrink(),
                    Expanded(child: widget.emptyState),
                    if (widget.addHeaderOrFooterEmptyState)
                      widget.footer ?? const SizedBox.shrink(),
                  ],
                ),
              )
            : CustomScrollBar(
                scrollController: _scrollController,
                galleryGroups: groups,
                inUseNotifier: scrollBarInUseNotifier,
                heighOfViewport: MediaQuery.sizeOf(context).height,
                topPadding: widget.disableVerticalPaddingForScrollbar
                    ? 0.0
                    : appBarPinnedHeight + groupHeaderExtent!,
                bottomPadding: widget.disableVerticalPaddingForScrollbar
                    ? ValueNotifier(0.0)
                    : scrollbarBottomPaddingNotifier,
                child: NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (notification) {
                    final renderBox =
                        _headerKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (renderBox != null) {
                      _headerHeightNotifier.value = renderBox.size.height;
                    } else {
                      _logger.info(
                        "Header render box is null, cannot get height",
                      );
                    }

                    return true;
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: _swipeActiveNotifier,
                        builder: (context, isSwipeActive, child) {
                          return Semantics(
                            identifier: _automationScrollIdentifier,
                            container: true,
                            child: CustomScrollView(
                              physics: widget.disableScroll || isSwipeActive
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                              controller: _scrollController,
                              slivers: [
                                if (widget.appBar != null)
                                  widget.appBar!.buildSliver(context),
                                SliverToBoxAdapter(
                                  child: SizeChangedLayoutNotifier(
                                    child: SizedBox(
                                      key: _headerKey,
                                      child:
                                          widget.header ??
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                                SectionedListSliver(
                                  sectionLayouts: groups.groupLayouts,
                                ),
                                SliverToBoxAdapter(child: widget.footer),
                              ],
                            ),
                          );
                        },
                      ),
                      groups.groupType.showGroupHeader() &&
                              !widget.disablePinnedGroupHeader
                          ? PinnedGroupHeader(
                              scrollController: _scrollController,
                              galleryGroups: groups,
                              headerHeightNotifier: _headerHeightNotifier,
                              scrollOffsetBase: appBarCollapseExtent,
                              topOffset: appBarPinnedHeight,
                              selectedFiles: widget.selectedFiles,
                              showSelectAll:
                                  widget.showSelectAll &&
                                  !widget.limitSelectionToOne,
                              scrollbarInUseNotifier: scrollBarInUseNotifier,
                              showGallerySettingsCTA:
                                  widget.showGallerySettingsCTA,
                            )
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _GalleryAppBarScrollBody extends StatelessWidget {
  const _GalleryAppBarScrollBody({
    required this.appBar,
    required this.physics,
    required this.child,
  });

  final GalleryAppBarConfig? appBar;
  final ScrollPhysics physics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appBarConfig = appBar;
    if (appBarConfig == null) {
      return child;
    }

    return CustomScrollView(
      physics: physics,
      slivers: [
        appBarConfig.buildSliver(context),
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }
}

class PinnedGroupHeader extends StatefulWidget {
  final ScrollController scrollController;
  final GalleryGroups galleryGroups;
  final ValueNotifier<double?> headerHeightNotifier;
  final double scrollOffsetBase;
  final double topOffset;
  final SelectedFiles? selectedFiles;
  final bool showSelectAll;
  final ValueNotifier<bool> scrollbarInUseNotifier;
  final bool showGallerySettingsCTA;
  static const kScaleDurationInMilliseconds = 200;
  static const kTrailingIconsFadeInDelayMs = 0;
  static const kTrailingIconsFadeInDurationMs = 200;

  const PinnedGroupHeader({
    required this.scrollController,
    required this.galleryGroups,
    required this.headerHeightNotifier,
    required this.scrollOffsetBase,
    required this.topOffset,
    required this.selectedFiles,
    required this.showSelectAll,
    required this.scrollbarInUseNotifier,
    required this.showGallerySettingsCTA,
    super.key,
  });

  @override
  State<PinnedGroupHeader> createState() => _PinnedGroupHeaderState();
}

class _PinnedGroupHeaderState extends State<PinnedGroupHeader>
    with BoundaryReporter {
  String? currentGroupId;
  final _enlargeHeader = ValueNotifier<bool>(false);
  Timer? _enlargeHeaderTimer;
  InheritedGalleryBoundaries? _boundariesProvider;
  Timer? _timer;
  bool lastInUseState = false;
  bool fadeInTrailingIcons = false;
  @override
  void initState() {
    super.initState();
    widget.scrollbarInUseNotifier.addListener(scrollbarInUseListener);
    widget.scrollController.addListener(_setCurrentGroupID);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _setBaseTopBoundary();
      }
    });
    widget.headerHeightNotifier.addListener(_headerHeightNotifierListener);
  }

  @override
  void didUpdateWidget(covariant PinnedGroupHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _setCurrentGroupID();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _boundariesProvider = GalleryBoundariesProvider.of(context);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_setCurrentGroupID);
    widget.scrollbarInUseNotifier.removeListener(scrollbarInUseListener);
    widget.headerHeightNotifier.removeListener(_headerHeightNotifierListener);
    _enlargeHeader.dispose();
    _enlargeHeaderTimer?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _setCurrentGroupID() {
    if (widget.headerHeightNotifier.value == null) return;
    final scrollOffset = _scrollOffset;
    if (scrollOffset == null) return;
    final normalizedScrollOffset =
        scrollOffset -
        widget.scrollOffsetBase -
        widget.headerHeightNotifier.value!;
    if (normalizedScrollOffset < 0) {
      _setBaseTopBoundary();
      if (currentGroupId == null) return;
      currentGroupId = null;
    } else {
      final groupScrollOffsets = widget.galleryGroups.groupScrollOffsets;

      int low = 0;
      int high = groupScrollOffsets.length - 1;
      int floorIndex = 0;

      if (normalizedScrollOffset < groupScrollOffsets.first) {
        return;
      }

      while (low <= high) {
        final mid = low + (high - low) ~/ 2;
        final midValue = groupScrollOffsets[mid];

        if (midValue <= normalizedScrollOffset) {
          floorIndex = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      if (currentGroupId ==
          widget
              .galleryGroups
              .scrollOffsetToGroupIdMap[groupScrollOffsets[floorIndex]]) {
        return;
      }
      currentGroupId = widget
          .galleryGroups
          .scrollOffsetToGroupIdMap[groupScrollOffsets[floorIndex]];
    }

    setState(() {});
    if (widget.scrollbarInUseNotifier.value) {
      if (Platform.isIOS) {
        HapticFeedback.selectionClick();
      } else {
        HapticFeedback.vibrate();
      }
    }
  }

  void _setBaseTopBoundary() {
    _boundariesProvider?.setTopBoundary(
      widget.topOffset > 0 ? widget.topOffset : null,
    );
  }

  double? get _scrollOffset {
    if (widget.scrollController.positions.length != 1) {
      return null;
    }
    return widget.scrollController.offset;
  }

  void scrollbarInUseListener() {
    _enlargeHeaderTimer?.cancel();
    if (widget.scrollbarInUseNotifier.value) {
      _enlargeHeader.value = true;
      lastInUseState = true;
      fadeInTrailingIcons = false;
    } else {
      _enlargeHeaderTimer = Timer(const Duration(milliseconds: 250), () {
        _enlargeHeader.value = false;
        if (lastInUseState) {
          fadeInTrailingIcons = true;
          Future.delayed(
            const Duration(
              milliseconds:
                  PinnedGroupHeader.kTrailingIconsFadeInDelayMs +
                  PinnedGroupHeader.kTrailingIconsFadeInDurationMs +
                  100,
            ),
            () {
              if (!mounted) return;
              setState(() {
                fadeInTrailingIcons = false;
              });
            },
          );
        }
        lastInUseState = false;
      });
    }
  }

  void _headerHeightNotifierListener() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      _setCurrentGroupID();
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = GalleryAppBarWidget.backgroundColor(context);
    final header = currentGroupId != null
        ? ValueListenableBuilder(
            valueListenable: _enlargeHeader,
            builder: (context, inUse, _) {
              return AnimatedScale(
                scale: inUse ? 1.2 : 1.0,
                alignment: Alignment.topLeft,
                duration: const Duration(
                  milliseconds: PinnedGroupHeader.kScaleDurationInMilliseconds,
                ),
                curve: Curves.easeInOutSine,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned.fill(
                      child: ClipRect(
                        clipper: _PinnedHeaderBottomShadowClipper(),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: backgroundColor,
                      child: boundaryWidget(
                        position: BoundaryPosition.top,
                        child: GroupHeaderWidget(
                          title: widget
                              .galleryGroups
                              .groupIdToGroupDataMap[currentGroupId!]!
                              .groupType
                              .getTitle(
                                context,
                                widget
                                    .galleryGroups
                                    .groupIDToFilesMap[currentGroupId]!
                                    .first,
                              ),
                          gridSize: localSettings.getPhotoGridSize(),
                          height: widget.galleryGroups.groupHeaderExtent,
                          filesInGroup: widget
                              .galleryGroups
                              .groupIDToFilesMap[currentGroupId!]!,
                          selectedFiles: widget.selectedFiles,
                          showSelectAll: widget.showSelectAll,
                          showGalleryLayoutSettingCTA:
                              widget.showGallerySettingsCTA,
                          showTrailingIcons: !inUse,
                          isPinnedHeader: true,
                          fadeInTrailingIcons: fadeInTrailingIcons,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          )
        : const SizedBox.shrink();

    if (widget.topOffset == 0) {
      return header;
    }

    return Padding(
      padding: EdgeInsets.only(top: widget.topOffset),
      child: header,
    );
  }
}

class _PinnedHeaderBottomShadowClipper extends CustomClipper<Rect> {
  const _PinnedHeaderBottomShadowClipper();

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, size.height, size.width, size.height + 8);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class GalleryIndexUpdatedEvent {
  final String tag;
  final int index;

  GalleryIndexUpdatedEvent(this.tag, this.index);
}
