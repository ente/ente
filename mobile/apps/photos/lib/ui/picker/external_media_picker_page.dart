import "dart:async";
import "dart:math";

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
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/components/selection_preview_button.dart";
import "package:photos/ui/device_picker/device_media_library.dart";
import "package:photos/ui/device_picker/device_picker_page.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/ui/viewer/search/search_suggestions.dart";

typedef _PickerSearchResults = ({
  List<EnteFile> files,
  List<SearchResult> suggestions,
});

class ExternalMediaPickerPage extends StatefulWidget {
  final MediaType? requestedType;
  final bool allowMultiple;

  const ExternalMediaPickerPage({
    this.requestedType,
    this.allowMultiple = false,
    super.key,
  });

  @override
  State<ExternalMediaPickerPage> createState() =>
      _ExternalMediaPickerPageState();
}

class _ExternalMediaPickerPageState extends State<ExternalMediaPickerPage> {
  final _selectedFiles = SelectedFiles(dedupeByUploadID: true);
  final _logger = Logger("ExternalMediaPicker");
  final _searchQueryService = SearchQueryService(SearchService.instance);
  final _subscriptions = <StreamSubscription<Event>>[];
  Future<Map<int, EnteFile>>? _searchFiles;
  Future<void>? _searchPreparation;
  int _searchGeneration = 0;
  final _searchController = TextEditingController();
  final _headerScrollController = ScrollController();
  final _searchDebouncer = Debouncer(const Duration(milliseconds: 314));
  late Future<List<Collection>> _albums = CollectionsService.instance
      .getCollectionForOnEnteSection();
  Stream<_PickerSearchResults>? _searchResults;
  GenericSearchResult? _searchResult;
  Collection? _collection;
  String _browseOriginQuery = "";
  String _query = "";
  bool _showAlbums = false;
  bool _isBusy = false;

  bool get _isBrowsingResult => _collection != null || _searchResult != null;

  @override
  void initState() {
    super.initState();
    for (final stream in <Stream<Event>>[
      Bus.instance.on<FilesUpdatedEvent>(),
      Bus.instance.on<BackupFoldersUpdatedEvent>(),
      Bus.instance.on<ForceReloadHomeGalleryEvent>(),
    ]) {
      _subscriptions.add(
        stream.listen((event) {
          _searchFiles = null;
          if (event is FilesUpdatedEvent &&
              const {
                EventType.deletedFromRemote,
                EventType.deletedFromEverywhere,
                EventType.archived,
                EventType.hide,
              }.contains(event.type)) {
            _selectedFiles.unSelectAll(event.updatedFiles.toSet());
          }
          if (event is ForceReloadHomeGalleryEvent) {
            final hidden = CollectionsService.instance
                .archivedOrHiddenCollectionIds();
            _selectedFiles.unSelectAll(
              _selectedFiles.files
                  .where((file) => hidden.contains(file.collectionID))
                  .toSet(),
            );
            setState(
              () => _albums = CollectionsService.instance
                  .getCollectionForOnEnteSection(),
            );
          }
          if (_query.isNotEmpty) {
            setState(() => _searchResults = null);
            _scheduleSearch();
          }
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.viewInsetsOf(context).bottom == 0 &&
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
    _searchDebouncer.cancelDebounce();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _searchController.dispose();
    _headerScrollController.dispose();
    _selectedFiles.dispose();
    super.dispose();
  }

  Future<FileLoadResult> _loadFiles(
    int creationStartTime,
    int creationEndTime, {
    int? limit,
    bool? asc,
  }) async {
    if (!isLocalGalleryMode && !Configuration.instance.hasConfiguredAccount()) {
      return FileLoadResult(<EnteFile>[], false);
    }
    final searchResult = _searchResult;
    final ownerID = Configuration.instance.getUserIDV2();
    final collectionsToHide = CollectionsService.instance
        .archivedOrHiddenCollectionIds();
    final filterOptions = DBFilterOptions(
      hideIgnoredForUpload: true,
      dedupeUploadID: true,
      ignoredCollectionIDs: collectionsToHide,
      ignoreSavedFiles: true,
      onlyUploadedFiles: true,
      ignoreSharedItems:
          _collection == null &&
          _searchResult == null &&
          _query.isEmpty &&
          localSettings.hideSharedItemsFromHomeGallery,
    );

    final FileLoadResult result;
    if (_collection != null) {
      final loaded = await FilesDB.instance.getFilesInCollection(
        _collection!.id,
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

    if (searchResult == null && widget.requestedType == null) {
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
      !collection.isArchived() &&
      !collection.isQuickLinkCollection() &&
      collection.type != CollectionType.uncategorized;

  RequestType get _deviceRequestType => switch (widget.requestedType) {
    MediaType.image => RequestType.image,
    MediaType.video => RequestType.video,
    null => RequestType.common,
  };

  Future<Set<String>> _accessibleDeviceAlbumIDs() async {
    try {
      final library = PhotoManagerDeviceLibrary(
        requestType: _deviceRequestType,
      );
      if (!(await library.permission(request: false)).hasAccess) {
        return <String>{};
      }
      return (await library.albums()).map((album) => album.id).toSet();
    } catch (error, stack) {
      _logger.warning("Could not search device folders", error, stack);
      return <String>{};
    }
  }

  Stream<_PickerSearchResults> _findFiles(String query, int generation) async* {
    try {
      final batches = _searchQueryService.search(
        context,
        query,
        collectionFilter: _isPickerCollection,
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
      final eligibleByID = await (_searchFiles ??=
          _loadFiles(galleryLoadStartTime, galleryLoadEndTime).then(
            (result) => {
              for (final file in result.files) file.uploadedFileID!: file,
            },
          ));
      var fileMatches = <EnteFile>[];
      final suggestions = <SearchResult>[];
      Future<Set<String>>? accessibleDeviceAlbumIDs;
      await for (final batch in batches) {
        var changed = false;
        for (final result in batch) {
          if (result is DeviceAlbumSearchResult) {
            final albumIDs = await (accessibleDeviceAlbumIDs ??=
                _accessibleDeviceAlbumIDs());
            if (albumIDs.contains(result.deviceCollection.id)) {
              suggestions.add(result);
              changed = true;
            }
          } else if (result is AlbumSearchResult) {
            suggestions.add(result);
            changed = true;
          } else if (result is GenericSearchResult) {
            final fileIDs = result
                .resultFiles()
                .map((file) => file.uploadedFileID)
                .toSet();
            var params = result.params;
            if (result.type() == ResultType.shared) {
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

  void _openCollection(Collection collection) {
    if (_isBusy || _isBrowsingResult) return;
    final query = _query;
    FocusScope.of(context).unfocus();
    _searchController.clear();
    _search("");
    setState(() {
      _browseOriginQuery = query;
      _collection = collection;
      _searchFiles = null;
    });
  }

  void _openSearchResult(GenericSearchResult result) {
    if (_isBusy || _isBrowsingResult) return;
    final query = _query;
    FocusScope.of(context).unfocus();
    _searchController.clear();
    _search("");
    setState(() {
      _browseOriginQuery = query;
      _searchResult = result;
      _searchFiles = null;
    });
  }

  Future<void> _pickFromDevice({String? initialAlbumID}) async {
    if (_isBusy) return;
    FocusScope.of(context).unfocus();
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
        requestType: _deviceRequestType,
        selectionLimit: widget.allowMultiple ? null : 1,
        initialSelection: initial,
        allowEmptySelection: initial.isNotEmpty,
      );
      if (result == null || !mounted) return;
      final knownFiles = await const PhotoManagerDeviceLibrary().files(
        result.map((asset) => asset.id).toList(),
      );
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

  bool _matchesRequestedType(EnteFile file) {
    switch (widget.requestedType) {
      case MediaType.image:
        return file.fileType == FileType.image ||
            file.fileType == FileType.livePhoto;
      case MediaType.video:
        return file.fileType == FileType.video;
      case null:
        return true;
    }
  }

  Future<void> _previewSelection() async {
    if (_isBusy || _selectedFiles.files.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isBusy = true);
    final files = _selectedFiles.files.toList();
    final bool? shouldAdd;
    try {
      shouldAdd = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => SelectionState(
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
                          showEditAction: false,
                          showGalleryFilmstrip: true,
                          selectionLimit: widget.allowMultiple ? null : 1,
                          onSelectionRemoved: (file) =>
                              _selectedFiles.unSelectAll({file}),
                        ),
                        bottomBar: _PickerActionBar(
                          selectedFiles: _selectedFiles,
                          isCompleting: false,
                          onCancel: () {
                            _selectedFiles.clearAll();
                            Navigator.pop(previewContext);
                          },
                          onDone: () async =>
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

  Future<void> _completeSelection() async {
    if (_isBusy || _selectedFiles.files.isEmpty) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    final selectedFiles = _selectedFiles.files.toList();
    final uris = <String>[];
    try {
      for (final file in selectedFiles) {
        final uri = await getPickerResultUri(file);
        if (uri == null) throw StateError("Could not prepare picker selection");
        uris.add(uri);
      }
      if (!mounted) return;
      if (!selectedFiles.every(_selectedFiles.isFileSelected)) {
        throw StateError("Picker selection changed while preparing media");
      }
      if (uris.length == 1) {
        await MediaExtension().setResult(uris.first);
      } else {
        await MediaExtension().setResults(uris);
      }
    } catch (error, stack) {
      _logger.warning("Could not return picker selection", error, stack);
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
        setState(() => _isBusy = false);
      }
      return;
    }
  }

  Future<void> _handleBack() async {
    if (_isBusy) {
      return;
    }
    if (_query.isNotEmpty) {
      _searchController.clear();
      _search("");
      return;
    }
    if (_isBrowsingResult) {
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
    await MediaExtension().cancelResult();
  }

  @override
  Widget build(BuildContext context) {
    final isBrowsingResult = _isBrowsingResult;
    final isShowingAlbums = _query.isEmpty && _showAlbums && !isBrowsingResult;
    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final selectionControlHeight = max(
      44.0,
      MediaQuery.textScalerOf(context).scale(TextStyles.body.fontSize!) *
              TextStyles.body.height! +
          Spacing.xxl,
    );
    final bottomPadding =
        (isShowingAlbums ? 0 : selectionControlHeight) +
        Spacing.md +
        MediaQuery.paddingOf(context).bottom;
    final deviceButton = ConstrainedBox(
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
    final pickerHeader = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: TextInputComponent(
            controller: _searchController,
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
        if (!isBrowsingResult)
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
                                  if (showAlbums) {
                                    _albums = CollectionsService.instance
                                        .getCollectionForOnEnteSection();
                                  }
                                }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                deviceButton,
              ],
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

    Widget content;
    if (_query.isNotEmpty) {
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
              : AbsorbPointer(
                  absorbing: _isBusy,
                  child: Padding(
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
                          DeviceAlbumSearchResult() => _pickFromDevice(
                            initialAlbumID: result.deviceCollection.id,
                          ),
                          GenericSearchResult() => _openSearchResult(result),
                          _ => null,
                        },
                      ),
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
    } else if (isShowingAlbums) {
      content = FutureBuilder<List<Collection>>(
        future: _albums,
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
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
                itemBuilder: (context, index) => AlbumListItemWidget(
                  snapshot.data![index],
                  onTapCallback: _isBusy ? null : _openCollection,
                ),
              ),
      );
    } else {
      content = gallery();
    }

    return PopScope(
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
                    tooltip: isBrowsingResult
                        ? context.strings.back
                        : context.strings.close,
                    icon: isBrowsingResult
                        ? const Icon(Icons.arrow_back, size: IconSizes.medium)
                        : const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: IconSizes.medium,
                          ),
                    onTap: _isBusy
                        ? null
                        : () => isBrowsingResult
                              ? _handleBack()
                              : MediaExtension().cancelResult(),
                  ),
                ),
                title: AnimatedBuilder(
                  animation: _selectedFiles,
                  builder: (context, _) {
                    final selectedCount = _selectedFiles.files.length;
                    return Text(
                      _searchResult?.name() ??
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
                    builder: (context, _) => _selectedFiles.files.isEmpty
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
                      child: LayoutBuilder(
                        builder: (context, viewport) => Stack(
                          children: [
                            Positioned.fill(
                              child: CustomScrollView(
                                controller: _headerScrollController,
                                primary: false,
                                physics: isKeyboardVisible
                                    ? null
                                    : const NeverScrollableScrollPhysics(),
                                slivers: [
                                  if (!isBrowsingResult)
                                    SliverToBoxAdapter(child: pickerHeader),
                                  SliverFillRemaining(
                                    child: ClipRect(child: content),
                                  ),
                                ],
                              ),
                            ),
                            if (!isShowingAlbums &&
                                viewport.maxHeight >=
                                    selectionControlHeight + Spacing.sm)
                              PositionedDirectional(
                                start: Spacing.lg,
                                end: Spacing.lg,
                                bottom: Spacing.sm,
                                child: Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: ListenableBuilder(
                                    listenable: _selectedFiles,
                                    builder: (context, _) {
                                      final count = _selectedFiles.files.length;
                                      final label = widget.allowMultiple
                                          ? context.strings.selectedCount(
                                              count: count,
                                            )
                                          : context.strings
                                                .selectedCountWithLimit(
                                                  count: count,
                                                  limit: 1,
                                                );
                                      return count == 0
                                          ? const SizedBox.shrink()
                                          : SelectionControlChip(
                                              label: widget.allowMultiple
                                                  ? count.toString()
                                                  : '$count/1',
                                              semanticLabel:
                                                  '${context.strings.clearSelection}, $label',
                                              icon: const HugeIcon(
                                                icon: HugeIcons
                                                    .strokeRoundedCancel01,
                                                size: IconSizes.small,
                                              ),
                                              onTap: _isBusy
                                                  ? null
                                                  : () => _selectedFiles
                                                        .clearAll(),
                                            );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        ),
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
                          isCompleting: _isBusy,
                          onCancel: () => _selectedFiles.clearAll(),
                          onDone: _completeSelection,
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
  }
}

class _PickerActionBar extends StatefulWidget {
  final SelectedFiles selectedFiles;
  final bool isCompleting;
  final VoidCallback onCancel;
  final Future<void> Function() onDone;

  const _PickerActionBar({
    required this.selectedFiles,
    required this.isCompleting,
    required this.onCancel,
    required this.onDone,
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
              : _PickerBottomActionBar(
                  key: const ValueKey("picker-action-bar"),
                  isCompleting: widget.isCompleting,
                  onCancel: widget.onCancel,
                  onDone: widget.onDone,
                ),
        );
        return GalleryBoundariesProvider.of(context) == null
            ? bar
            : boundaryWidget(position: BoundaryPosition.bottom, child: bar);
      },
    );
  }
}

class _PickerBottomActionBar extends StatelessWidget {
  final bool isCompleting;
  final VoidCallback onCancel;
  final Future<void> Function() onDone;

  const _PickerBottomActionBar({
    required this.isCompleting,
    required this.onCancel,
    required this.onDone,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final widthOfScreen = MediaQuery.sizeOf(context).width;
    final leftRightPadding = widthOfScreen > restrictedMaxWidth
        ? (widthOfScreen - restrictedMaxWidth) / 2
        : 0.0;
    return Container(
      color: context.componentColors.backgroundBase,
      padding: EdgeInsets.fromLTRB(
        leftRightPadding + 16,
        16,
        leftRightPadding + 16,
        bottomPadding + 16,
      ),
      child: Row(
        children: [
          Expanded(
            child: ButtonWidgetV2(
              buttonType: ButtonTypeV2.secondary,
              buttonSize: ButtonSizeV2.large,
              labelText: context.strings.cancel,
              isDisabled: isCompleting,
              shouldSurfaceExecutionStates: false,
              onTap: isCompleting
                  ? null
                  : () async {
                      onCancel();
                    },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ButtonWidgetV2(
              buttonType: ButtonTypeV2.primary,
              buttonSize: ButtonSizeV2.large,
              labelText: context.strings.done,
              isDisabled: isCompleting,
              onTap: isCompleting ? null : onDone,
            ),
          ),
        ],
      ),
    );
  }
}
