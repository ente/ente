import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_components/hugeicons.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:media_extension/media_extension.dart";
import "package:media_extension/media_extension_action_types.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/user_config.dart";
import "package:photos/db/files_db.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/backup_folders_updated_event.dart";
import "package:photos/events/event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/force_reload_home_gallery_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/search/album_search_result.dart";
import "package:photos/models/search/device_album_search_result.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/module/share/picker_result_uri.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filter/db_filters.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/search_query_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/album/list_item.dart";
import "package:photos/ui/components/selection_preview_button.dart";
import "package:photos/ui/device_picker/device_media_library.dart";
import "package:photos/ui/device_picker/device_picker_controller.dart";
import "package:photos/ui/device_picker/device_picker_page.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/picker/local_media_picker_search.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/ui/viewer/gallery/swipe_selection_wrapper.dart";
import "package:photos/ui/viewer/search/search_suggestions.dart";

typedef _PickerSearchResults = ({
  List<EnteFile> files,
  List<SearchResult> suggestions,
});

typedef _PickerAlbums = (List<Collection>, Set<int>);

class ExternalMediaPickerPage extends StatelessWidget {
  final MediaType? requestedType;
  final bool allowMultiple;

  const ExternalMediaPickerPage({
    this.requestedType,
    this.allowMultiple = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final requestType = switch (requestedType) {
      MediaType.image => RequestType.image,
      MediaType.video => RequestType.video,
      null => RequestType.common,
    };
    Widget picker([DevicePickerContents? local]) => _Picker(
      requestType: requestType,
      allowMultiple: allowMultiple,
      local: local,
    );
    if (!isLocalGalleryMode) return picker();
    return DevicePickerPage(
      requestType: requestType,
      selectionLimit: allowMultiple ? null : 1,
      contentBuilder: picker,
    );
  }
}

class _Picker extends StatefulWidget {
  const _Picker({
    required this.requestType,
    required this.allowMultiple,
    this.local,
  });

  final RequestType requestType;
  final bool allowMultiple;
  final DevicePickerContents? local;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> with WidgetsBindingObserver {
  final _selectedFiles = SelectedFiles(dedupeByUploadID: true);
  final _logger = Logger("ExternalMediaPicker");
  final _searchQueryService = SearchQueryService(SearchService.instance);
  final _subscriptions = <StreamSubscription<Event>>[];
  Future<Map<int, EnteFile>>? _searchFiles;
  Future<Set<int>>? _excludedFileIDs;
  Future<Set<int>>? _hiddenFileIDs;
  bool _checkSelectedAlbums = false;
  Future<void>? _searchPreparation;
  int _searchGeneration = 0;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _headerScrollController = ScrollController();
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 314));
  Future<_PickerAlbums>? _albums;
  Stream<_PickerSearchResults>? _searchResults;
  GenericSearchResult? _searchResult;
  Collection? _collection;
  String _browseOriginQuery = "";
  String _query = "";
  bool _keyboardVisible = false;
  bool _keyboardRequested = false;
  bool _backStartedInSearch = false;
  bool _showAlbums = false;
  bool _isBusy = false;
  List<EnteFile>? _preparingFiles;

  bool _refreshingDevice = false;
  Completer<void>? _deviceCheck;
  bool _deviceCheckFailed = false;
  ({Route<dynamic> route, List<EnteFile> files})? _preview;
  bool get _verifyingAccess => _deviceCheck != null || _deviceCheckFailed;
  AssetPathEntity? get _deviceFolder => widget.local?.model.browsedFolder;

  bool get _isBrowsingResult =>
      _collection != null || _searchResult != null || _deviceFolder != null;
  bool get _isShowingAlbums =>
      _showAlbums && _query.isEmpty && !_isBrowsingResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final device = widget.local?.model;
    if (device != null) {
      _refreshingDevice = device.refreshing;
      if (_refreshingDevice) _deviceCheck = Completer<void>();
      device.addListener(_deviceChanged);
      _subscriptions.add(
        Bus.instance.on<LocalPhotosUpdatedEvent>().listen((_) {
          if (_query.isNotEmpty &&
              device.hasAccess &&
              !device.refreshing &&
              !_searchDebouncer.isActive()) {
            _scheduleSearch();
          }
        }),
      );
      return;
    }
    for (final stream in <Stream<Event>>[
      Bus.instance.on<FilesUpdatedEvent>(),
      Bus.instance.on<BackupFoldersUpdatedEvent>(),
      Bus.instance.on<ForceReloadHomeGalleryEvent>(),
    ]) {
      _subscriptions.add(
        stream.listen((event) {
          _searchFiles = null;
          _excludedFileIDs = _hiddenFileIDs = null;
          final checkRemoved =
              event is FilesUpdatedEvent &&
              event.type == EventType.deletedFromRemote &&
              _selectedFiles.files.isNotEmpty &&
              (event.updatedFiles.isEmpty ||
                  event.updatedFiles.any(_selectedFiles.isFileSelected));
          if (checkRemoved) _checkSelectedAlbums = true;
          if (event is FilesUpdatedEvent &&
              const {
                EventType.deletedFromEverywhere,
                EventType.archived,
                EventType.hide,
              }.contains(event.type)) {
            _selectedFiles.unSelectAll(event.updatedFiles.toSet());
          }
          if ((checkRemoved || event is ForceReloadHomeGalleryEvent) &&
              _selectedFiles.files.any((file) => file.isUploaded)) {
            unawaited(
              _refreshSelectionVisibility().catchError((
                Object error,
                StackTrace stack,
              ) {
                _logger.warning(
                  "Could not refresh picker selection",
                  error,
                  stack,
                );
              }),
            );
          }
          _albums = null;
          if (_isShowingAlbums) setState(() {});
          if (_query.isNotEmpty) {
            setState(() => _searchResults = null);
            _scheduleSearch();
          }
        }),
      );
    }
  }

  void _deviceChanged() {
    final device = widget.local!.model;
    if (_refreshingDevice == device.refreshing) return;
    _refreshingDevice = device.refreshing;
    if (device.refreshing) {
      _deviceCheck?.complete();
      _deviceCheck = Completer<void>();
      ++_searchGeneration;
      _searchDebouncer.cancelDebounce();
      _searchResults = null;
    } else {
      if (!device.hasAccess || device.error != null) {
        if (!device.hasAccess) {
          _removeUnavailable(_selectedFiles.files.toSet());
          if (_searchResult != null) {
            _searchResult = null;
            _searchController.text = _query = _browseOriginQuery;
          }
        }
        _closePreview();
        _finishDeviceCheck(failed: device.error != null);
        return;
      }
      if (_query.isNotEmpty) _scheduleSearch();
      if (_selectedFiles.files.isNotEmpty ||
          _searchResult != null ||
          _preview != null) {
        unawaited(_checkLocalMedia(device));
      } else {
        _finishDeviceCheck();
      }
    }
  }

  void _finishDeviceCheck({bool failed = false}) {
    _deviceCheckFailed = failed;
    _deviceCheck?.complete();
    _deviceCheck = null;
  }

  void _removeUnavailable(Set<EnteFile> files) {
    if (!files.any(_selectedFiles.isFileSelected)) return;
    _selectedFiles.unSelectAll(files);
    if (ModalRoute.of(context)?.isCurrent == true ||
        _preview?.route.isCurrent == true) {
      showToastComponent(context, context.strings.devicePickerSelectionChanged);
    }
  }

  void _trackPreview(Route<dynamic> route, List<EnteFile> files) {
    if (identical(_preview?.route, route)) return;
    _preview = (route: route, files: files);
    unawaited(
      route.popped.then((_) {
        if (_preview?.route == route) _preview = null;
      }),
    );
  }

  void _closePreview() {
    final route = _preview?.route;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  Future<void> _checkLocalMedia(DevicePickerController device) async {
    final check = _deviceCheck;
    final selected = _selectedFiles.files.toList();
    final resultFiles = _searchResult?.resultFiles();
    final preview = _preview;
    bool isCurrent() => mounted && identical(_deviceCheck, check);
    try {
      final missingIDs =
          [
              ...selected,
              ...?resultFiles,
              ...?preview?.files,
            ].map((file) => file.localID).nonNulls.toSet()
            ..removeWhere(device.hasLoadedMedia);
      final remaining = await accessiblePickerAssets(
        device,
        missingIDs,
        isCurrent,
      );
      if (!isCurrent()) return;
      missingIDs.removeAll(remaining.keys);
      bool missing(EnteFile file) =>
          file.localID == null || missingIDs.contains(file.localID);
      _removeUnavailable(selected.where(missing).toSet());
      if (preview != null &&
          preview == _preview &&
          preview.files.any(missing)) {
        _closePreview();
      }
      resultFiles?.removeWhere(missing);
      setState(_finishDeviceCheck);
    } catch (error, stack) {
      _logger.warning("Could not check device media", error, stack);
      if (!isCurrent()) return;
      _closePreview();
      setState(() => _finishDeviceCheck(failed: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (visible) _keyboardRequested = false;
    if (_keyboardVisible && !visible && _backStartedInSearch) {
      _searchFocusNode.unfocus();
    }
    _keyboardVisible = visible;
    if (!visible &&
        _headerScrollController.hasClients &&
        _headerScrollController.offset != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _headerScrollController.hasClients) {
          _headerScrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishDeviceCheck();
    widget.local?.model.removeListener(_deviceChanged);
    _searchDebouncer.cancelDebounce();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _headerScrollController.dispose();
    _selectedFiles.dispose();
    super.dispose();
  }

  Future<Set<int>> get _excludedUploadIDs =>
      _excludedFileIDs ??= _loadExcludedUploadIDs();

  Future<Set<int>> get _hiddenUploadIDs =>
      _hiddenFileIDs ??= _loadExcludedUploadIDs(includeArchived: true);

  Future<Set<int>> _loadExcludedUploadIDs({
    bool includeArchived = false,
  }) async {
    try {
      final collections = CollectionsService.instance;
      final ids = await FilesDB.instance.getUploadedFileIDsInCollections(
        includeArchived
            ? collections.getHiddenCollectionIds()
            : collections.archivedOrHiddenCollectionIds(),
      );
      return ids.toSet();
    } catch (_) {
      _excludedFileIDs = _hiddenFileIDs = null;
      rethrow;
    }
  }

  Future<void> _refreshSelectionVisibility() async {
    final query = _hiddenUploadIDs;
    final excluded = await query;
    final removed = <EnteFile>{};
    final replacements = <int, EnteFile>{};
    if (_checkSelectedAlbums) {
      final pairs = {
        for (final file in _selectedFiles.files)
          if (file.uploadedFileID != null && file.collectionID != null)
            (file.uploadedFileID!, file.collectionID!),
      };
      final existing = await FilesDB.instance.getExistingFileIDsByCollection(
        pairs,
      );
      removed.addAll(
        _selectedFiles.files.where(
          (file) =>
              pairs.contains((file.uploadedFileID, file.collectionID)) &&
              existing[file.collectionID]?.contains(file.uploadedFileID) !=
                  true,
        ),
      );
      if (removed.isNotEmpty) {
        final copies = await FilesDB.instance.getFilesFromIDs([
          for (final file in removed) file.uploadedFileID!,
        ]);
        for (final copy in copies) {
          if (copy.collectionID != null && _isEligible(copy, excluded)) {
            replacements[copy.uploadedFileID!] = copy;
          }
        }
      }
    }
    if (!mounted) return;
    if (_hiddenFileIDs != query) return _refreshSelectionVisibility();
    _checkSelectedAlbums = false;
    if (excluded.isNotEmpty) {
      removed.addAll(
        _selectedFiles.files.where(
          (file) => excluded.contains(file.uploadedFileID),
        ),
      );
    }
    if (removed.any(_selectedFiles.files.contains)) {
      _selectedFiles.replaceSelection({
        for (final file in _selectedFiles.files)
          if (removed.contains(file))
            ?replacements[file.uploadedFileID]
          else
            file,
      });
    }
  }

  Future<_PickerAlbums> _loadAlbums() => (
    CollectionsService.instance.getCollectionForOnEnteSection(),
    _excludedUploadIDs,
  ).wait;

  Future<FileLoadResult> _loadFiles(
    int creationStartTime,
    int creationEndTime, {
    int? limit,
    bool? asc,
  }) async {
    if (!Configuration.instance.hasConfiguredAccount()) {
      return FileLoadResult(<EnteFile>[], false);
    }
    final searchResult = _searchResult;
    final ownerID = Configuration.instance.getUserIDV2();
    final collection = _collection;
    final filterOptions = DBFilterOptions(
      hideIgnoredForUpload: true,
      dedupeUploadID: true,
      ignoredCollectionIDs: collection == null
          ? CollectionsService.instance.archivedOrHiddenCollectionIds()
          : null,
      ignoreSavedFiles: true,
      onlyUploadedFiles: true,
      ignoreSharedItems:
          _collection == null &&
          _searchResult == null &&
          _query.isEmpty &&
          localSettings.hideSharedItemsFromHomeGallery,
    );

    final FileLoadResult result;
    if (collection != null) {
      final loaded = await FilesDB.instance.getFilesInCollection(
        collection.id,
        creationStartTime,
        creationEndTime,
        limit: limit,
        asc: asc,
      );
      result = FileLoadResult(
        await applyDBFilters(
          loaded.files
              .where(
                (file) => file.magicMetadata.visibility == visibleVisibility,
              )
              .toList(),
          filterOptions,
        ),
        loaded.hasMore,
      );
    } else {
      result = await FilesDB.instance.getAllPendingOrUploadedFiles(
        creationStartTime,
        creationEndTime,
        ownerID,
        limit: limit,
        asc: asc,
        filterOptions: filterOptions,
      );
    }

    final excluded = await (_isSearchOnlyAlbum(collection)
        ? _hiddenUploadIDs
        : _excludedUploadIDs);
    if (excluded.isNotEmpty) {
      result.files.removeWhere(
        (file) => excluded.contains(file.uploadedFileID),
      );
    }
    if (searchResult == null && widget.requestType == RequestType.common) {
      return result;
    }

    Iterable<EnteFile> files = result.files;
    if (searchResult != null) {
      final filesByID = {
        for (final file in result.files) file.uploadedFileID: file,
      };
      files = searchResult
          .resultFiles()
          .map((file) => filesByID[file.uploadedFileID])
          .nonNulls;
    }
    return FileLoadResult(
      files.where(_matchesRequestedType).toList(),
      result.hasMore,
    );
  }

  void _search(String value) {
    if (_isBrowsingResult) return;
    final query = value.trim();
    if (query == _query) return;
    _searchDebouncer.cancelDebounce();
    setState(() {
      _query = query;
      _searchResults = null;
    });
    if (query.isEmpty) {
      _searchGeneration++;
      return;
    }
    _scheduleSearch();
  }

  void _scheduleSearch() {
    final generation = ++_searchGeneration;
    _searchDebouncer.run(() async {
      if (!mounted || _query.isEmpty) return;
      setState(() => _searchResults = _findFiles(_query, generation));
    });
  }

  bool _isPickerCollection(Collection collection) =>
      !collection.isHidden() &&
      !_isSearchOnlyAlbum(collection) &&
      collection.type != CollectionType.uncategorized;

  bool _isSearchOnlyAlbum(Collection? collection) =>
      collection != null &&
      (collection.isArchived() || collection.isQuickLinkCollection());

  bool _isEligible(EnteFile file, Set<int> excluded) =>
      file.isUploaded &&
      file.magicMetadata.visibility == visibleVisibility &&
      !excluded.contains(file.uploadedFileID) &&
      _matchesRequestedType(file);

  Future<List<DeviceAlbumSearchResult>> _accessibleDeviceAlbums(
    Iterable<DeviceAlbumSearchResult> matches,
  ) async {
    try {
      final library = PhotoManagerDeviceLibrary(
        requestType: widget.requestType,
      );
      if (!(await library.permission(request: false)).hasAccess) {
        return [];
      }
      final albums = {
        for (final album in await library.albums()) album.id: album,
      };
      final folders = matches
          .map((match) => albums[match.deviceCollection.id])
          .nonNulls;
      final results = await Future.wait(
        folders.map((album) => deviceAlbumPickerResult(library, album)),
      );
      return results.nonNulls.toList();
    } catch (error, stack) {
      _logger.warning("Could not search device folders", error, stack);
      return [];
    }
  }

  Stream<_PickerSearchResults> _findFiles(String query, int generation) async* {
    try {
      final device = widget.local?.model;
      final batches = _searchQueryService.search(
        context,
        query,
        deviceAlbumSearch: device == null
            ? null
            : () => searchLocalPickerAlbums(device, query),
        magicSearch: () async {
          final service = SemanticSearchService.instance;
          final preparation = _searchPreparation ??= service
              .prepareForInteractiveSearch();
          await preparation;
          if (!service.isMagicSearchEnabledAndReady() &&
              identical(_searchPreparation, preparation)) {
            _searchPreparation = null;
          }
          if (!mounted ||
              generation != _searchGeneration ||
              query != _query ||
              _isBrowsingResult) {
            return <SearchResult>[];
          }
          return SearchService.instance.getMagicSearchResults(context, query);
        },
      );
      final localFiles = <String, EnteFile?>{};
      final Map<Object, EnteFile?> eligibleByID = device != null
          ? localFiles
          : await (_searchFiles ??=
                _loadFiles(galleryLoadStartTime, galleryLoadEndTime).then(
                  (result) => {
                    for (final file in result.files) file.uploadedFileID!: file,
                  },
                ));
      Object? fileID(EnteFile file) =>
          device == null ? file.uploadedFileID : file.localID;
      bool isCurrent() => mounted && generation == _searchGeneration;
      var fileMatches = <EnteFile>[];
      final suggestions = <SearchResult>[];
      await for (final batch in batches) {
        if (device != null) {
          if (!device.hasAccess || !isCurrent()) return;
          await resolveLocalSearchFiles(
            device,
            batch.whereType<GenericSearchResult>().expand(
              (result) => result.resultFiles(),
            ),
            localFiles,
            isCurrent,
          );
          if (!isCurrent()) return;
        }
        var changed = false;
        final deviceMatches = batch.whereType<DeviceAlbumSearchResult>();
        if (deviceMatches.isNotEmpty) {
          final folders = device == null
              ? await _accessibleDeviceAlbums(deviceMatches)
              : deviceMatches;
          suggestions.addAll(folders);
          changed = folders.isNotEmpty;
        }
        for (final result in batch) {
          if (result is AlbumSearchResult && device == null) {
            final album = result.collectionWithThumbnail;
            final cover = album.thumbnail;
            var thumbnail = eligibleByID[cover?.uploadedFileID];
            if (cover != null && _isSearchOnlyAlbum(album.collection)) {
              final hidden = await _hiddenUploadIDs;
              thumbnail = _isEligible(cover, hidden) ? cover : null;
            }
            suggestions.add(
              AlbumSearchResult(
                CollectionWithThumbnail(album.collection, thumbnail),
              ),
            );
            changed = true;
          } else if (result is GenericSearchResult) {
            final fileIDs = result.resultFiles().map(fileID).toSet();
            var params = result.params;
            if (device == null && result.type() == ResultType.shared) {
              final collections =
                  (params[kContactCollections] as List<Collection>? ?? const [])
                      .where(_isPickerCollection)
                      .toList();
              try {
                fileIDs.addAll(
                  await FilesDB.instance.getUploadedFileIDsInCollections(
                    collections.map((collection) => collection.id).toSet(),
                  ),
                );
              } catch (error, stack) {
                _logger.warning("Could not search shared albums", error, stack);
              }
              params = {...params, kContactCollections: collections};
            }
            final files = fileIDs
                .map((id) => eligibleByID[id])
                .nonNulls
                .toList();
            if (files.isEmpty) continue;
            changed = true;
            if (result.type() == ResultType.shared ||
                result.type() == ResultType.file ||
                result.type() == ResultType.faces) {
              files.sort(
                (a, b) => (b.creationTime ?? 0).compareTo(a.creationTime ?? 0),
              );
            }
            if (result.type() == ResultType.file) {
              fileMatches = [...fileMatches, ...files];
            } else {
              suggestions.add(
                GenericSearchResult(
                  result.type(),
                  result.name(),
                  files,
                  hierarchicalSearchFilter: result
                      .getHierarchicalSearchFilter(),
                  params: params,
                ),
              );
            }
          }
        }
        if (changed) {
          yield (files: fileMatches, suggestions: suggestions.toList());
        }
      }
    } catch (error, stack) {
      _searchFiles = null;
      _logger.warning("Could not search picker media", error, stack);
      rethrow;
    }
  }

  void _browse(VoidCallback open) {
    if (_isBusy || _isBrowsingResult) return;
    final query = _query;
    _dismissSearch();
    _searchController.clear();
    _search("");
    setState(() {
      _browseOriginQuery = query;
      _searchFiles = null;
      open();
    });
  }

  void _openCollection(Collection collection) =>
      _browse(() => _collection = collection);

  void _openFolder(AssetPathEntity folder, {bool filenameMatches = false}) {
    final device = widget.local!.model;
    _browse(
      () =>
          unawaited(device.openAlbum(folder, filenameMatches: filenameMatches)),
    );
  }

  Future<void> _pickFromDevice({String? initialAlbumID}) async {
    if (_isBusy) return;
    _dismissSearch();
    final device = widget.local?.model;
    if (device != null) {
      final folder = device.albums
          .where((a) => a.id == initialAlbumID)
          .firstOrNull;
      if (folder != null) _openFolder(folder);
      return;
    }
    setState(() => _isBusy = true);
    try {
      final files = _selectedFiles.files.toList();
      final initial = <AssetEntity>[];
      final initialFiles = Set<EnteFile>.identity();
      for (var offset = 0; offset < files.length; offset += 8) {
        final assets = await Future.wait(
          files.skip(offset).take(8).map((file) => file.getAsset),
        );
        if (!mounted) return;
        for (final (index, asset) in assets.indexed) {
          if (asset == null) continue;
          initial.add(asset);
          initialFiles.add(files[offset + index]);
        }
      }
      final initialUploadedIDs = initialFiles
          .map((file) => file.uploadedFileID)
          .nonNulls
          .toSet();
      final result = await showDevicePicker(
        context,
        initialAlbumID: initialAlbumID,
        requestType: widget.requestType,
        selectionLimit: widget.allowMultiple ? null : 1,
        initialSelection: initial,
        allowEmptySelection: initial.isNotEmpty,
      );
      if (result == null || !mounted) return;
      var knownFiles = <String, EnteFile>{};
      try {
        final files = await const PhotoManagerDeviceLibrary().files(
          result.map((asset) => asset.id).toList(),
        );
        if (files.isNotEmpty) {
          final excluded = await _hiddenUploadIDs;
          files.removeWhere(
            (_, file) => excluded.contains(file.uploadedFileID),
          );
        }
        knownFiles = files;
      } catch (error, stack) {
        _logger.warning("Could not read device file metadata", error, stack);
      }
      if (!mounted) return;
      _selectedFiles.replaceSelection({
        if (widget.allowMultiple)
          ..._selectedFiles.files.where(
            (file) =>
                file.isUploaded &&
                !initialFiles.contains(file) &&
                !initialUploadedIDs.contains(file.uploadedFileID),
          ),
        for (final asset in result)
          knownFiles[asset.id] ?? fileFromAsset('', asset),
      });
    } catch (error, stack) {
      _logger.warning("Could not pick device media", error, stack);
      if (mounted) showShortToast(context, context.strings.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  bool _matchesRequestedType(EnteFile file) => switch (widget.requestType) {
    RequestType.image =>
      file.fileType == FileType.image || file.fileType == FileType.livePhoto,
    RequestType.video => file.fileType == FileType.video,
    _ => true,
  };

  Future<void> _previewSelection() async {
    if (_isBusy || _selectedFiles.files.isEmpty) return;
    _dismissSearch();
    setState(() => _isBusy = true);
    final files = _selectedFiles.files.toList();
    final bool? shouldAdd;
    try {
      shouldAdd = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => SelectionState.preview(
            files: files,
            onPreview: widget.local == null ? null : _trackPreview,
            selectedFiles: _selectedFiles,
            child: Theme(
              data: darkThemeData,
              child: Builder(
                builder: (previewContext) =>
                    AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle.light.copyWith(
                        systemNavigationBarColor:
                            previewContext.componentColors.backgroundBase,
                      ),
                      child: DetailPage(
                        DetailPageConfiguration(
                          files,
                          files.length - 1,
                          "external_media_picker_selection",
                          mode: DetailPageMode.selection,
                          isLocalOnlyContext: widget.local != null,
                          showEditAction: false,
                          showGalleryFilmstrip: true,
                          selectionLimit: widget.allowMultiple ? null : 1,
                          onSelectionRemoved: (file) =>
                              _selectedFiles.unSelectAll({file}),
                        ),
                        bottomBar: _PickerActionBar(
                          selectedFiles: _selectedFiles,
                          isCompleting: false,
                          onAdd: () async =>
                              Navigator.pop(previewContext, true),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
    if (!mounted || shouldAdd != true) return;
    if (files.length == _selectedFiles.files.length &&
        files.every(_selectedFiles.isFileSelected)) {
      await _completeSelection();
    }
  }

  Future<List<String>?> _localPickerUris(
    DevicePickerController device,
    List<EnteFile> selected,
  ) async {
    bool current() => mounted && identical(_preparingFiles, selected);
    final route = ModalRoute.of(context);
    bool canReturn() =>
        !_deviceCheckFailed &&
        device.hasAccess &&
        route?.isCurrent == true &&
        _selectedFiles.files.containsAll(selected);
    while (current()) {
      if (_deviceCheck case final check?) {
        await check.future;
        continue;
      }
      if (!canReturn()) return null;
      final albums = device.albums;
      try {
        final assets = await accessiblePickerAssets(
          device,
          selected.map((file) => file.localID).nonNulls,
          current,
        );
        if (!current()) return null;
        if (_deviceCheck != null || !identical(albums, device.albums)) continue;
        final missing = selected
            .where((file) => !assets.containsKey(file.localID))
            .toSet();
        if (missing.isNotEmpty) {
          _removeUnavailable(missing);
          return null;
        }
        final uris = <String>[];
        for (final file in selected) {
          final uri =
              await assets[file.localID]!.getMediaUrl() ??
              (await getFile(file))?.uri.toString();
          if (!current()) return null;
          if (uri == null) throw StateError("Could not prepare device item");
          uris.add(uri);
        }
        while (_deviceCheck != null) {
          await _deviceCheck!.future;
          if (!current()) return null;
        }
        return canReturn() ? uris : null;
      } catch (_) {
        if (_deviceCheck == null && identical(albums, device.albums)) rethrow;
      }
    }
    return null;
  }

  Future<void> _completeSelection() async {
    if (_isBusy || _selectedFiles.files.isEmpty) {
      return;
    }
    final selectedFiles = _selectedFiles.files.toList();
    setState(() {
      _isBusy = true;
      _preparingFiles = selectedFiles;
    });
    final uris = <String>[];
    try {
      final device = widget.local?.model;
      if (device != null) {
        final localUris = await _localPickerUris(device, selectedFiles);
        if (!mounted || _preparingFiles != selectedFiles) return;
        if (localUris == null) return;
        uris.addAll(localUris);
      } else {
        for (final file in selectedFiles) {
          final uri = await getPickerResultUri(file).onError((error, stack) {
            _logger.warning("Could not prepare picker item", error, stack);
            return null;
          });
          if (!mounted || _preparingFiles != selectedFiles) return;
          if (uri != null) uris.add(uri);
        }
        if (selectedFiles.any((file) => file.isUploaded)) {
          await _refreshSelectionVisibility();
          if (!mounted || _preparingFiles != selectedFiles) return;
        }
      }
      if (uris.isEmpty || !_selectedFiles.files.containsAll(selectedFiles)) {
        throw StateError("Picker selection is no longer available");
      }
      await _finishPicker(
        () => uris.length == 1
            ? MediaExtension().setResult(uris.first)
            : MediaExtension().setResults(uris),
      );
    } catch (error, stack) {
      if (!mounted || _preparingFiles != selectedFiles) return;
      _logger.warning("Could not prepare picker selection", error, stack);
      showShortToast(context, context.strings.somethingWentWrong);
    } finally {
      if (mounted && _preparingFiles == selectedFiles) {
        setState(() {
          _isBusy = false;
          _preparingFiles = null;
        });
      }
    }
  }

  Future<void> _finishPicker(Future<void> Function() finish) async {
    if (_isBusy && _preparingFiles == null) return;
    setState(() {
      _isBusy = true;
      _preparingFiles = null;
    });
    try {
      await finish();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent) _backStartedInSearch = false;
    return (_editingSearch || _backStartedInSearch) &&
        ModalRoute.isCurrentOf(context) == true;
  }

  bool get _editingSearch =>
      _searchFocusNode.hasFocus && (_keyboardVisible || _keyboardRequested);

  @override
  void handleCommitBackGesture() => _dismissSearch();

  void _dismissSearch() {
    _backStartedInSearch = _keyboardRequested = false;
    _searchFocusNode.unfocus();
  }

  Future<void> _handleBack() async {
    final dismissInput = _editingSearch || _backStartedInSearch;
    _dismissSearch();
    if (dismissInput) return;
    if (_isBusy || _refreshingDevice) {
      return;
    }
    if (_query.isNotEmpty) {
      _searchController.clear();
      _search("");
      return;
    }
    if (_isBrowsingResult) {
      if (_deviceFolder != null) {
        final recent = widget.local!.model.recentAlbum;
        if (recent != null) unawaited(widget.local!.model.openAlbum(recent));
      }
      setState(() {
        _searchResult = null;
        _collection = null;
        _searchFiles = null;
      });
      _searchController.text = _browseOriginQuery;
      _search(_browseOriginQuery);
      return;
    }
    if (_selectedFiles.files.isNotEmpty) {
      _selectedFiles.clearAll();
      return;
    }
    await _finishPicker(MediaExtension().cancelResult);
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.local;
    final localResultFiles = local == null
        ? null
        : _searchResult?.resultFiles();
    final isBrowsingResult = _isBrowsingResult;
    final showBack = isBrowsingResult && _preparingFiles == null;
    final bottomPadding = Spacing.md + MediaQuery.paddingOf(context).bottom;
    late final deviceButton = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width / 2,
      ),
      child: ButtonComponent(
        label: context.strings.onDevice,
        variant: ButtonComponentVariant.secondary,
        size: ButtonComponentSize.small,
        density: ButtonComponentDensity.compact,
        leading: const Icon(Icons.folder_copy_outlined, size: IconSizes.small),
        isDisabled: _isBusy,
        shouldSurfaceExecutionStates: false,
        shouldShowSuccessState: false,
        onTap: _pickFromDevice,
      ),
    );
    Widget revealTabs(Widget tabs) {
      final visible = !_keyboardVisible && _query.isEmpty;
      const hidden = SizedBox(width: double.infinity);
      if (MediaQuery.disableAnimationsOf(context)) {
        return visible ? tabs : hidden;
      }
      return AnimatedCrossFade(
        duration: Motion.standard,
        sizeCurve: Curves.easeOutCubic,
        crossFadeState: visible
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: hidden,
        secondChild: tabs,
      );
    }

    final pickerHeader = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: TapRegion(
            onTapInside: (_) {
              _backStartedInSearch = false;
              _keyboardRequested = !_keyboardVisible;
            },
            onTapOutside: (event) {
              _backStartedInSearch =
                  _editingSearch &&
                  isSystemBackGestureEdge(context, event.position.dx);
              if (!_backStartedInSearch) _dismissSearch();
            },
            onTapUpOutside: (event) {
              if (_backStartedInSearch &&
                  isSystemBackGestureEdge(context, event.position.dx)) {
                _dismissSearch();
              }
            },
            child: TextInputComponent(
              groupId: _searchFocusNode,
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: context.strings.searchPhotosPeoplePlaces,
              isClearable: true,
              isDisabled: _isBusy,
              prefix: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch01,
                size: 18,
                color: context.componentColors.textLight,
              ),
              onChanged: _search,
            ),
          ),
        ),
        revealTabs(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              0,
              Spacing.md,
              Spacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: [
                      for (final (showAlbums, label) in [
                        (false, context.strings.photos),
                        (true, context.strings.albums),
                      ])
                        FilterChipComponent(
                          label: label,
                          showSelectedTrailing: false,
                          state: _showAlbums == showAlbums
                              ? FilterChipComponentState.selected
                              : FilterChipComponentState.unselected,
                          onChanged: _isBusy
                              ? null
                              : (_) => setState(() {
                                  _showAlbums = showAlbums;
                                  _albums = null;
                                }),
                        ),
                    ],
                  ),
                ),
                if (local == null) ...[
                  const SizedBox(width: Spacing.sm),
                  deviceButton,
                ],
              ],
            ),
          ),
        ),
        const DividerComponent(),
      ],
    );
    Widget gallery({List<EnteFile>? files, Widget? header}) => Gallery(
      key: ValueKey((_collection?.id, _searchResult, _query, files)),
      initialFiles: files,
      asyncLoader: files == null
          ? _loadFiles
          : (start, end, {limit, asc}) async {
              final result = files
                  .where(
                    (file) =>
                        (file.creationTime ?? 0) >= start &&
                        (file.creationTime ?? 0) <= end,
                  )
                  .toList();
              return FileLoadResult(result, false);
            },
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>(),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.archived,
        EventType.hide,
      },
      forceReloadEvents: [
        Bus.instance.on<BackupFoldersUpdatedEvent>(),
        Bus.instance.on<ForceReloadHomeGalleryEvent>(),
      ],
      tagPrefix: "external_media_picker",
      selectedFiles: _selectedFiles,
      header: header,
      scrollInitialPlaceholder: true,
      footer: SizedBox(height: bottomPadding),
      inSelectionMode: true,
      limitSelectionToOne: !widget.allowMultiple,
      showSelectAll: false,
      disableSelection: _isBusy,
      emptyState: Center(child: Text(context.strings.noResultsFound)),
      galleryType: GalleryType.homepage,
      enableFileGrouping: _searchResult?.type() != ResultType.magic,
      reloadDebounceTime: const Duration(seconds: 2),
      reloadDebounceExecutionInterval: const Duration(seconds: 5),
      priorityReloadDebounceTime: const Duration(milliseconds: 200),
    );

    Widget withGalleryTopBoundary(Widget child) => LayoutBuilder(
      builder: (context, _) {
        final boundaries = GalleryBoundariesProvider.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            boundaries?.setTopBoundary(box.localToGlobal(Offset.zero).dy);
          }
        });
        return child;
      },
    );

    Widget content;
    if (_deviceCheckFailed && _deviceCheck == null) {
      content = Center(
        child: ButtonComponent(
          label: context.strings.retry,
          onTap: () => local!.model.refresh(),
        ),
      );
    } else if (local != null && (_verifyingAccess || !local.model.hasAccess)) {
      content = _verifyingAccess
          ? const Center(child: LoadingComponent())
          : local.media(_selectedFiles);
    } else if (_query.isNotEmpty) {
      content = StreamBuilder<_PickerSearchResults>(
        key: ValueKey(_query),
        stream: _searchResults,
        builder: (context, snapshot) {
          final waiting =
              _searchResults == null ||
              snapshot.connectionState == ConnectionState.waiting;
          final files = waiting ? <EnteFile>[] : snapshot.data?.files ?? [];
          final suggestions = waiting
              ? <SearchResult>[]
              : snapshot.data?.suggestions ?? [];
          if (files.isEmpty &&
              suggestions.isEmpty &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: LoadingComponent());
          }
          if (snapshot.hasError) {
            return Center(child: Text(context.strings.somethingWentWrong));
          }
          final header = suggestions.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: SearchResultsSectionsWidget(
                    query: _query,
                    results: suggestions,
                    resultBuilder: (result) => SearchResultsWidgetGenerator(
                      result,
                      onResultTap: () => switch (result) {
                        AlbumSearchResult() => _openCollection(
                          result.collectionWithThumbnail.collection,
                        ),
                        PickerFilenameResult() => _openFolder(
                          result.album,
                          filenameMatches: true,
                        ),
                        DeviceAlbumSearchResult() => _pickFromDevice(
                          initialAlbumID: result.deviceCollection.id,
                        ),
                        GenericSearchResult() => _browse(
                          () => _searchResult = result,
                        ),
                        _ => null,
                      },
                    ),
                  ),
                );
          if (files.isEmpty && header != null) {
            return ListView(
              padding: EdgeInsets.only(bottom: bottomPadding),
              children: [header],
            );
          }
          return gallery(files: files, header: header);
        },
      );
    } else if (local != null && _searchResult == null) {
      content = _isShowingAlbums
          ? local.albums(_openFolder)
          : withGalleryTopBoundary(local.media(_selectedFiles));
    } else if (_isShowingAlbums) {
      content = FutureBuilder<_PickerAlbums>(
        future: _albums ??= _loadAlbums(),
        builder: (context, snapshot) =>
            snapshot.connectionState != ConnectionState.done
            ? const Center(child: LoadingComponent())
            : snapshot.hasError
            ? Center(child: Text(context.strings.somethingWentWrong))
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  bottomPadding,
                ),
                itemCount: snapshot.data!.$1.length,
                separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) => AlbumListItemWidget(
                  snapshot.data!.$1[index],
                  canShowCover: (file) => _isEligible(file, snapshot.data!.$2),
                  onTapCallback: _isBusy ? null : _openCollection,
                ),
              ),
      );
    } else if (_searchResult?.type() == ResultType.magic) {
      content = withGalleryTopBoundary(gallery(files: localResultFiles));
    } else {
      content = gallery(files: localResultFiles);
    }

    final picker = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        unawaited(_handleBack());
      },
      child: GalleryBoundariesProvider(
        child: GalleryFilesState(
          child: SelectionState(
            selectedFiles: _selectedFiles,
            respectSystemGestureInsets: true,
            onPreview: local == null ? null : _trackPreview,
            child: Scaffold(
              backgroundColor: context.componentColors.backgroundBase,
              appBar: AppBar(
                backgroundColor: context.componentColors.backgroundBase,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: Center(
                  child: IconButtonComponent(
                    variant: IconButtonComponentVariant.unfilled,
                    size: 48,
                    tooltip: showBack
                        ? context.strings.back
                        : context.strings.close,
                    icon: showBack
                        ? const Icon(Icons.arrow_back, size: IconSizes.medium)
                        : const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: IconSizes.medium,
                          ),
                    onTap: _isBusy && _preparingFiles == null
                        ? null
                        : showBack
                        ? _handleBack
                        : () => _finishPicker(MediaExtension().cancelResult),
                  ),
                ),
                title: AnimatedBuilder(
                  animation: _selectedFiles,
                  builder: (context, _) {
                    final selectedCount = _selectedFiles.files.length;
                    return Text(
                      _searchResult?.name() ??
                          _deviceFolder?.name ??
                          _collection?.displayName ??
                          (selectedCount == 0
                              ? context.strings.selectItemsToAdd
                              : context.strings.selectedPhotos(
                                  count: selectedCount,
                                )),
                      style: getEnteTextTheme(context).largeBold,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                actions: [
                  ListenableBuilder(
                    listenable: _selectedFiles,
                    builder: (context, _) =>
                        _selectedFiles.files.isEmpty || _verifyingAccess
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: Spacing.sm,
                            ),
                            child: SizedBox.square(
                              dimension: 48,
                              child: SelectionPreviewButton(
                                file: _selectedFiles.files.last,
                                count: _selectedFiles.files.length,
                                onTap: _isBusy ? null : _previewSelection,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, constraints) => Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        controller: _headerScrollController,
                        primary: false,
                        physics: _keyboardVisible
                            ? null
                            : const NeverScrollableScrollPhysics(),
                        slivers: [
                          if (!isBrowsingResult)
                            SliverToBoxAdapter(child: pickerHeader),
                          SliverFillRemaining(
                            child: ClipRect(
                              child: AbsorbPointer(
                                absorbing: _isBusy,
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: _PickerActionBar(
                          selectedFiles: _selectedFiles,
                          isCompleting: _isBusy || _verifyingAccess,
                          onAdd: _completeSelection,
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
    );
    return TextFieldTapRegion(groupId: _searchFocusNode, child: picker);
  }
}

class _PickerActionBar extends StatefulWidget {
  final SelectedFiles selectedFiles;
  final bool isCompleting;
  final Future<void> Function() onAdd;

  const _PickerActionBar({
    required this.selectedFiles,
    required this.isCompleting,
    required this.onAdd,
  });

  @override
  State<_PickerActionBar> createState() => _PickerActionBarState();
}

class _PickerActionBarState extends State<_PickerActionBar>
    with BoundaryReporter {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.selectedFiles,
      builder: (context, _) {
        final selectedCount = widget.selectedFiles.files.length;
        final bar = AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: selectedCount == 0
              ? const SizedBox.shrink()
              : ColoredBox(
                  color: context.componentColors.backgroundBase,
                  child: SafeArea(
                    top: false,
                    child: PickerAddButton(
                      isDisabled: widget.isCompleting,
                      onTap: widget.onAdd,
                    ),
                  ),
                ),
        );
        return GalleryBoundariesProvider.of(context) == null
            ? bar
            : boundaryWidget(position: BoundaryPosition.bottom, child: bar);
      },
    );
  }
}
