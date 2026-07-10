import "dart:async";
import "dart:math";

import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import 'package:logging/logging.dart';
import "package:path_provider/path_provider.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import 'package:photos/core/event_bus.dart';
import 'package:photos/data/holidays.dart';
import 'package:photos/data/months.dart';
import 'package:photos/data/years.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import 'package:photos/events/local_photos_updated_event.dart';
import "package:photos/extensions/user_extension.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/device_collection.dart';
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/location_tag/location_tag.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/ml/face/person.dart";
import 'package:photos/models/search/album_search_result.dart';
import 'package:photos/models/search/device_album_search_result.dart';
import 'package:photos/models/search/generic_search_result.dart';
import "package:photos/models/search/hierarchical/camera_filter.dart";
import "package:photos/models/search/hierarchical/contacts_filter.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/file_type_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/location_filter.dart";
import "package:photos/models/search/hierarchical/magic_filter.dart";
import "package:photos/models/search/hierarchical/top_level_generic_filter.dart";
import "package:photos/models/search/hierarchical/uploader_filter.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import 'package:photos/services/collections_service.dart';
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/services/date_parse_service.dart";
import "package:photos/services/filter/db_filters.dart";
import "package:photos/services/location_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import 'package:photos/services/machine_learning/semantic_search/semantic_search_service.dart';
import "package:photos/services/memories_cache_service.dart";
import "package:photos/services/photos_contacts_service.dart";
import "package:photos/states/location_screen_state.dart";
import "package:photos/ui/viewer/location/add_location_sheet.dart";
import "package:photos/ui/viewer/location/location_screen.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/ui/viewer/people/people_page.dart";
import "package:photos/ui/viewer/search/result/magic_result_screen.dart";
import "package:photos/utils/cache_util.dart";
import "package:photos/utils/file_util.dart";
import "package:photos/utils/people_sort_util.dart";

class SearchService {
  Future<List<EnteFile>>? _cachedFilesFuture;
  Future<List<EnteFile>>? _cachedFilesForSearch;
  Future<List<EnteFile>>? _cachedFilesForHierarchicalSearch;
  Future<List<EnteFile>>? _cachedFilesForGenericGallery;
  Future<List<EnteFile>>? _cachedFilesForOfflineGallery;
  Future<List<EnteFile>>? _cachedHiddenFilesFuture;
  final _logger = Logger((SearchService).toString());
  final _collectionService = CollectionsService.instance;
  static const _maximumResultsLimit = 20;
  late final mlDataDB = MLDataDB.instance;
  StreamSubscription<LocalPhotosUpdatedEvent>? _localPhotosUpdatedSubscription;

  SearchService._privateConstructor();

  static final SearchService instance = SearchService._privateConstructor();

  void init() {
    _localPhotosUpdatedSubscription?.cancel();
    _localPhotosUpdatedSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .listen((event) {
          // only invalidate, let the load happen on demand
          _cachedFilesFuture = null;
          _cachedFilesForSearch = null;
          _cachedFilesForHierarchicalSearch = null;
          _cachedFilesForGenericGallery = null;
          _cachedFilesForOfflineGallery = null;
          _cachedHiddenFilesFuture = null;
        });
  }

  Set<int> ignoreCollections() {
    return CollectionsService.instance.getHiddenCollectionIds();
  }

  Map<String, dynamic> _contactSearchParams(
    User user,
    List<Collection> collections,
  ) {
    final params = <String, dynamic>{
      kPersonParamID: user.linkedPersonID,
      kContactUserId: user.id,
      kContactEmail: resolveKnownEmail(user) ?? user.email,
      kContactCollections: collections,
    };
    return params;
  }

  Future<void> _warmContactsCacheIfNeeded() async {
    if (!PhotosContactsService.instance.needsWarmup) {
      return;
    }
    try {
      await PhotosContactsService.instance.ensureReady();
    } catch (e, s) {
      _logger.warning(
        "Failed to preload contacts cache; falling back to person/email results",
        e,
        s,
      );
    }
  }

  Future<GenericSearchResult?> buildContactSearchResultForUser(
    User user,
  ) async {
    final userId = user.id;
    if (userId == null || userId <= 0) {
      return null;
    }

    await _warmContactsCacheIfNeeded();

    final allFiles = await getAllFilesForSearch();
    final files = allFiles.where((file) => file.ownerID == userId).toList();
    final collections = _collectionService
        .getCollectionsForUI(includedShared: true, includeCollab: true)
        .where((collection) => _isVisibleSharedCollectionForContact(collection))
        .where((collection) => _isSameContactUser(collection.owner, user))
        .toList();

    return GenericSearchResult(
      ResultType.shared,
      resolveDisplayName(user),
      files,
      hierarchicalSearchFilter: ContactsFilter(
        user: user,
        occurrence: kMostRelevantFilter,
        matchedUploadedIDs: filesToUploadedFileIDs(files),
      ),
      params: _contactSearchParams(user, collections),
    );
  }

  bool _isVisibleSharedCollectionForContact(Collection collection) {
    final ownerID = Configuration.instance.getUserID();
    return !collection.isHidden() &&
        ownerID != null &&
        !collection.isOwner(ownerID);
  }

  bool _isSameContactUser(User source, User target) {
    final sourceId = source.id;
    final targetId = target.id;
    if (sourceId != null && targetId != null && sourceId > 0 && targetId > 0) {
      return sourceId == targetId;
    }
    return source.email == target.email;
  }

  Future<List<EnteFile>> getAllFilesForSearch() async {
    if (_cachedFilesFuture != null && _cachedFilesForSearch != null) {
      return _cachedFilesForSearch!;
    }

    if (_cachedFilesFuture == null) {
      _logger.info("Reading all files from db");
      _cachedFilesFuture = FilesDB.instance.getAllFilesFromDB(
        ignoreCollections(),
        dedupeByUploadId: false,
      );
    }

    _cachedFilesForSearch = _cachedFilesFuture!.then((files) {
      return applyDBFilters(files, DBFilterOptions(dedupeUploadID: true));
    });

    return _cachedFilesForSearch!;
  }

  Future<bool> hasAnyFilesForSearch() async {
    if (_cachedFilesFuture != null && _cachedFilesForSearch != null) {
      return (await _cachedFilesForSearch!).isNotEmpty;
    }

    return FilesDB.instance.hasAnyFile();
  }

  Future<List<EnteFile>> getAllFilesForHierarchicalSearch() async {
    if (_cachedFilesFuture != null &&
        _cachedFilesForHierarchicalSearch != null) {
      return _cachedFilesForHierarchicalSearch!;
    }

    if (_cachedFilesFuture == null) {
      _logger.info("Reading all files from db");
      _cachedFilesFuture = FilesDB.instance.getAllFilesFromDB(
        ignoreCollections(),
        dedupeByUploadId: false,
      );
    }

    _cachedFilesForHierarchicalSearch = _cachedFilesFuture!.then((files) {
      return applyDBFilters(
        files,
        DBFilterOptions(dedupeUploadID: false, onlyUploadedFiles: true),
      );
    });

    return _cachedFilesForHierarchicalSearch!;
  }

  Future<List<EnteFile>> getAllFilesForGenericGallery({
    bool onlyUploadedFiles = true,
  }) async {
    if (_cachedFilesFuture != null) {
      if (onlyUploadedFiles && _cachedFilesForGenericGallery != null) {
        return _cachedFilesForGenericGallery!;
      }
      if (!onlyUploadedFiles && _cachedFilesForOfflineGallery != null) {
        return _cachedFilesForOfflineGallery!;
      }
    }

    if (_cachedFilesFuture == null) {
      _logger.info("Reading all files from db");
      _cachedFilesFuture = FilesDB.instance.getAllFilesFromDB(
        ignoreCollections(),
        dedupeByUploadId: false,
      );
    }

    final filteredFiles = _cachedFilesFuture!.then((files) {
      return applyDBFilters(
        files,
        DBFilterOptions(
          dedupeUploadID: true,
          onlyUploadedFiles: onlyUploadedFiles,
        ),
      );
    });

    if (onlyUploadedFiles) {
      _cachedFilesForGenericGallery = filteredFiles;
      return _cachedFilesForGenericGallery!;
    } else {
      _cachedFilesForOfflineGallery = filteredFiles;
      return _cachedFilesForOfflineGallery!;
    }
  }

  Future<List<EnteFile>> getAllFilesForContactPhotoPicker() async {
    final files = await getAllFilesForSearch();
    final archivedCollectionIds =
        (await _collectionService.getArchivedCollection())
            .map((collection) => collection.id)
            .toSet();
    if (archivedCollectionIds.isEmpty) {
      return files;
    }
    return files
        .where((file) => !archivedCollectionIds.contains(file.collectionID))
        .toList();
  }

  Future<List<EnteFile>> getHiddenFiles() async {
    if (_cachedHiddenFilesFuture != null) {
      return _cachedHiddenFilesFuture!;
    }
    _logger.info("Reading hidden files from db");
    final hiddenCollections = CollectionsService.instance
        .getHiddenCollectionIds();
    _cachedHiddenFilesFuture = FilesDB.instance.getAllFilesFromCollections(
      hiddenCollections,
    );
    return _cachedHiddenFilesFuture!;
  }

  void clearCache() {
    _cachedFilesFuture = null;
    _cachedFilesForSearch = null;
    _cachedFilesForHierarchicalSearch = null;
    _cachedFilesForGenericGallery = null;
    _cachedFilesForOfflineGallery = null;
    _cachedHiddenFilesFuture = null;
    unawaited(memoriesCacheService.clearMemoriesCache());
  }

  // getFilteredCollectionsWithThumbnail removes deleted or archived or
  // collections which don't have a file from search result
  Future<List<AlbumSearchResult>> getCollectionSearchResults(
    String query,
  ) async {
    if (isLocalGalleryMode) {
      return <AlbumSearchResult>[];
    }
    final List<Collection> collections = _collectionService.getCollectionsForUI(
      includedShared: true,
    );

    final List<AlbumSearchResult> collectionSearchResults = [];

    for (var c in collections) {
      if (collectionSearchResults.length >= _maximumResultsLimit) {
        break;
      }

      if (!c.isHidden() &&
          c.type != CollectionType.uncategorized &&
          c.displayName.toLowerCase().contains(query.toLowerCase())) {
        final EnteFile? thumbnail = await _collectionService.getCover(c);
        collectionSearchResults.add(
          AlbumSearchResult(CollectionWithThumbnail(c, thumbnail)),
        );
      }
    }

    return collectionSearchResults;
  }

  Future<List<AlbumSearchResult>> getAllCollectionSearchResults(
    int? limit,
  ) async {
    try {
      if (isLocalGalleryMode) {
        return <AlbumSearchResult>[];
      }
      final List<Collection> collections = _collectionService
          .getCollectionsForUI(includedShared: true);

      final List<AlbumSearchResult> collectionSearchResults = [];

      for (var c in collections) {
        if (limit != null && collectionSearchResults.length >= limit) {
          break;
        }

        if (!c.isHidden() && c.type != CollectionType.uncategorized) {
          final EnteFile? thumbnail = await _collectionService.getCover(c);
          collectionSearchResults.add(
            AlbumSearchResult(CollectionWithThumbnail(c, thumbnail)),
          );
        }
      }

      return collectionSearchResults;
    } catch (e) {
      _logger.severe("error gettin allCollectionSearchResults", e);
      return [];
    }
  }

  Future<List<DeviceAlbumSearchResult>> getDeviceCollectionSearchResults(
    String query,
  ) async {
    try {
      final List<DeviceCollection> deviceCollections = await FilesDB.instance
          .getDeviceCollections(includeCoverThumbnail: true);

      final List<DeviceAlbumSearchResult> results = [];

      for (var dc in deviceCollections) {
        if (results.length >= _maximumResultsLimit) {
          break;
        }

        if (dc.name.toLowerCase().contains(query.toLowerCase())) {
          results.add(DeviceAlbumSearchResult(dc));
        }
      }

      return results;
    } catch (e) {
      _logger.severe("error getting deviceCollectionSearchResults", e);
      return [];
    }
  }

  Future<List<GenericSearchResult>> getYearSearchResults(
    String yearFromQuery,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    for (var yearData in YearsData.instance.yearsData) {
      if (yearData.year.startsWith(yearFromQuery)) {
        final List<EnteFile> filesInYear = await _getFilesInYear(
          yearData.duration,
        );
        if (filesInYear.isNotEmpty) {
          searchResults.add(
            GenericSearchResult(
              ResultType.year,
              yearData.year,
              filesInYear,
              hierarchicalSearchFilter: TopLevelGenericFilter(
                filterName: yearData.year,
                occurrence: kMostRelevantFilter,
                filterResultType: ResultType.year,
                matchedUploadedIDs: filesToUploadedFileIDs(filesInYear),
                filterIcon: HugeIcons.strokeRoundedCalendar03,
              ),
            ),
          );
        }
      }
    }
    return searchResults;
  }

  Future<List<GenericSearchResult>> getMagicSectionResults(
    BuildContext context, {
    int? limit,
  }) async {
    if (hasGrantedMLConsent) {
      final results = await magicCacheService.getMagicGenericSearchResult(
        context,
      );
      return limit == null
          ? results
          : results.take(limit).toList(growable: false);
    } else {
      return <GenericSearchResult>[];
    }
  }

  Future<List<GenericSearchResult>> getMonthSearchResults(
    BuildContext context,
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    final matchingMonths = _getMatchingMonths(context, query).toList();
    for (final month in matchingMonths) {
      final matchedFiles = await FilesDB.instance
          .getFilesCreatedWithinDurations(
            _getDurationsOfMonthInEveryYear(month.monthNumber),
            ignoreCollections(),
            order: 'DESC',
          );
      if (matchedFiles.isNotEmpty) {
        searchResults.add(
          GenericSearchResult(
            ResultType.month,
            month.name,
            matchedFiles,
            hierarchicalSearchFilter: TopLevelGenericFilter(
              filterName: month.name,
              occurrence: kMostRelevantFilter,
              filterResultType: ResultType.month,
              matchedUploadedIDs: filesToUploadedFileIDs(matchedFiles),
              filterIcon: HugeIcons.strokeRoundedCalendar03,
            ),
          ),
        );
      }
    }
    return searchResults;
  }

  Future<List<GenericSearchResult>> getHolidaySearchResults(
    BuildContext context,
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    if (query.isEmpty) {
      return searchResults;
    }
    final holidays = getHolidays(context);

    for (var holiday in holidays) {
      if (holiday.name.toLowerCase().contains(query.toLowerCase())) {
        final matchedFiles = await FilesDB.instance
            .getFilesCreatedWithinDurations(
              _getDurationsForCalendarDateInEveryYear(
                holiday.day,
                holiday.month,
              ),
              ignoreCollections(),
              order: 'DESC',
            );
        if (matchedFiles.isNotEmpty) {
          searchResults.add(
            GenericSearchResult(
              ResultType.event,
              holiday.name,
              matchedFiles,
              hierarchicalSearchFilter: TopLevelGenericFilter(
                filterName: holiday.name,
                occurrence: kMostRelevantFilter,
                filterResultType: ResultType.event,
                matchedUploadedIDs: filesToUploadedFileIDs(matchedFiles),
                filterIcon: HugeIcons.strokeRoundedCalendar03,
              ),
            ),
          );
        }
      }
    }
    return searchResults;
  }

  GenericSearchResult _buildFileTypeSearchResult(
    FileType fileType,
    String typeName,
    List<EnteFile> files,
  ) {
    return GenericSearchResult(
      ResultType.fileType,
      typeName,
      files,
      hierarchicalSearchFilter: FileTypeFilter(
        fileType: fileType,
        typeName: typeName,
        occurrence: kMostRelevantFilter,
        matchedUploadedIDs: filesToUploadedFileIDs(files),
      ),
    );
  }

  GenericSearchResult _buildFileExtensionSearchResult(
    String extensionName,
    List<EnteFile> files,
  ) {
    return GenericSearchResult(
      ResultType.fileExtension,
      extensionName,
      files,
      hierarchicalSearchFilter: TopLevelGenericFilter(
        filterName: extensionName,
        occurrence: kMostRelevantFilter,
        filterResultType: ResultType.fileExtension,
        matchedUploadedIDs: filesToUploadedFileIDs(files),
        filterIcon: HugeIcons.strokeRoundedFile01,
      ),
    );
  }

  String _fileExtension(String fileName) {
    final extensionSeparatorIndex = fileName.lastIndexOf(".");
    if (extensionSeparatorIndex < 0 ||
        extensionSeparatorIndex == fileName.length - 1) {
      return "";
    }
    return fileName.substring(extensionSeparatorIndex + 1).toUpperCase();
  }

  Future<GenericSearchResult> getFileTypeResult({
    required FileType fileType,
    required String typeName,
  }) async {
    final allFiles = await getAllFilesForSearch();
    final matchedFiles = allFiles.where((e) => e.fileType == fileType).toList();
    return _buildFileTypeSearchResult(fileType, typeName, matchedFiles);
  }

  Future<GenericSearchResult> getFileExtensionResult({
    required String extension,
    required String extensionName,
  }) async {
    final normalizedExtension = extension.startsWith(".")
        ? extension.substring(1).toUpperCase()
        : extension.toUpperCase();
    final allFiles = await getAllFilesForSearch();
    final matchedFiles = allFiles
        .where(
          (file) => _fileExtension(file.displayName) == normalizedExtension,
        )
        .toList();
    return _buildFileExtensionSearchResult(extensionName, matchedFiles);
  }

  Future<List<GenericSearchResult>> getFileTypeResults(
    BuildContext context,
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    final List<EnteFile> allFiles = await getAllFilesForSearch();
    for (var fileType in FileType.values) {
      if (!context.mounted) return const [];
      final String fileTypeString = getHumanReadableString(context, fileType);
      if (fileTypeString.toLowerCase().startsWith(query.toLowerCase())) {
        final matchedFiles = allFiles
            .where((e) => e.fileType == fileType)
            .toList();
        if (matchedFiles.isNotEmpty) {
          searchResults.add(
            _buildFileTypeSearchResult(fileType, fileTypeString, matchedFiles),
          );
        }
      }
    }
    return searchResults;
  }

  Future<List<GenericSearchResult>> getAllFileTypesAndExtensionsResults(
    BuildContext context,
    int? limit,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    final List<EnteFile> allFiles = await getAllFilesForSearch();
    final fileTypesAndMatchingFiles = <FileType, List<EnteFile>>{};
    final extensionsAndMatchingFiles = <String, List<EnteFile>>{};
    try {
      for (EnteFile file in allFiles) {
        if (!fileTypesAndMatchingFiles.containsKey(file.fileType)) {
          fileTypesAndMatchingFiles[file.fileType] = <EnteFile>[];
        }
        fileTypesAndMatchingFiles[file.fileType]!.add(file);

        final ext = _fileExtension(file.displayName);

        if (ext != "") {
          if (!extensionsAndMatchingFiles.containsKey(ext)) {
            extensionsAndMatchingFiles[ext] = <EnteFile>[];
          }
          extensionsAndMatchingFiles[ext]!.add(file);
        }
      }

      fileTypesAndMatchingFiles.forEach((key, value) {
        final name = getHumanReadableString(context, key);
        searchResults.add(_buildFileTypeSearchResult(key, name, value));
      });

      extensionsAndMatchingFiles.forEach((key, value) {
        searchResults.add(_buildFileExtensionSearchResult(key + "s", value));
      });

      if (limit != null) {
        return searchResults.sublist(0, min(limit, searchResults.length));
      } else {
        return searchResults;
      }
    } catch (e) {
      _logger.severe("Error getting allFileTypesAndExtensionsResults", e);
      return [];
    }
  }

  Future<List<GenericSearchResult>> getCaptionAndNameResults(
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    if (query.isEmpty) {
      return searchResults;
    }
    final RegExp pattern = RegExp(query, caseSensitive: false);
    final List<EnteFile> allFiles = await getAllFilesForSearch();
    final List<EnteFile> captionMatch = <EnteFile>[];
    final List<EnteFile> displayNameMatch = <EnteFile>[];
    final Map<String, List<EnteFile>> uploaderToFile = {};
    final Map<String, List<EnteFile>> cameraMakeToFiles = {};
    final Map<String, List<EnteFile>> cameraModelToFiles = {};
    for (EnteFile eachFile in allFiles) {
      if (eachFile.caption != null && pattern.hasMatch(eachFile.caption!)) {
        captionMatch.add(eachFile);
      }
      if (pattern.hasMatch(eachFile.displayName)) {
        displayNameMatch.add(eachFile);
      }
      if (eachFile.uploaderName != null &&
          pattern.hasMatch(eachFile.uploaderName!)) {
        if (!uploaderToFile.containsKey(eachFile.uploaderName!)) {
          uploaderToFile[eachFile.uploaderName!] = [];
        }
        uploaderToFile[eachFile.uploaderName!]!.add(eachFile);
      }
      final cameraMake = eachFile.cameraMake;
      if (cameraMake != null && pattern.hasMatch(cameraMake)) {
        cameraMakeToFiles.putIfAbsent(cameraMake, () => []).add(eachFile);
      }
      final cameraModel = eachFile.cameraModel;
      if (cameraModel != null && pattern.hasMatch(cameraModel)) {
        cameraModelToFiles.putIfAbsent(cameraModel, () => []).add(eachFile);
      }
    }
    if (captionMatch.isNotEmpty) {
      searchResults.add(
        GenericSearchResult(
          ResultType.fileCaption,
          query,
          captionMatch,
          hierarchicalSearchFilter: TopLevelGenericFilter(
            filterName: query,
            occurrence: kMostRelevantFilter,
            filterResultType: ResultType.fileCaption,
            matchedUploadedIDs: filesToUploadedFileIDs(captionMatch),
            filterIcon: HugeIcons.strokeRoundedText,
          ),
        ),
      );
    }
    if (displayNameMatch.isNotEmpty) {
      searchResults.add(
        GenericSearchResult(
          ResultType.file,
          query,
          displayNameMatch,
          hierarchicalSearchFilter: TopLevelGenericFilter(
            filterName: query,
            occurrence: kMostRelevantFilter,
            filterResultType: ResultType.file,
            matchedUploadedIDs: filesToUploadedFileIDs(displayNameMatch),
          ),
        ),
      );
    }
    if (uploaderToFile.isNotEmpty) {
      for (MapEntry<String, List<EnteFile>> entry in uploaderToFile.entries) {
        searchResults.add(
          GenericSearchResult(
            ResultType.uploader,
            entry.key,
            entry.value,
            hierarchicalSearchFilter: UploaderFilter(
              uploaderName: entry.key,
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: filesToUploadedFileIDs(entry.value),
            ),
          ),
        );
      }
    }
    if (cameraMakeToFiles.isNotEmpty) {
      for (final entry in cameraMakeToFiles.entries) {
        searchResults.add(
          GenericSearchResult(
            ResultType.cameraMake,
            entry.key,
            entry.value,
            hierarchicalSearchFilter: TopLevelGenericFilter(
              filterName: entry.key,
              occurrence: kMostRelevantFilter,
              filterResultType: ResultType.cameraMake,
              matchedUploadedIDs: filesToUploadedFileIDs(entry.value),
              filterIcon: HugeIcons.strokeRoundedCamera01,
            ),
          ),
        );
      }
    }
    if (cameraModelToFiles.isNotEmpty) {
      for (final entry in cameraModelToFiles.entries) {
        searchResults.add(
          GenericSearchResult(
            ResultType.cameraModel,
            entry.key,
            entry.value,
            hierarchicalSearchFilter: CameraFilter(
              cameraModel: entry.key,
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: filesToUploadedFileIDs(entry.value),
            ),
          ),
        );
      }
    }
    return searchResults;
  }

  Future<List<GenericSearchResult>> getFileExtensionResults(
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    if (!query.startsWith(".")) {
      return searchResults;
    }

    final List<EnteFile> allFiles = await getAllFilesForSearch();
    final Map<String, List<EnteFile>> resultMap = <String, List<EnteFile>>{};

    for (EnteFile eachFile in allFiles) {
      final String fileName = eachFile.displayName;
      if (fileName.contains(query)) {
        final String exnType = _fileExtension(fileName);
        if (exnType.isEmpty) {
          continue;
        }
        if (!resultMap.containsKey(exnType)) {
          resultMap[exnType] = <EnteFile>[];
        }
        resultMap[exnType]!.add(eachFile);
      }
    }
    for (MapEntry<String, List<EnteFile>> entry in resultMap.entries) {
      searchResults.add(
        _buildFileExtensionSearchResult(entry.key.toUpperCase(), entry.value),
      );
    }
    return searchResults;
  }

  Future<List<String>> getTopTwoFaces() async {
    final searchFilter = await SectionType.face
        .getData(null)
        .then(
          (value) => (value as List<GenericSearchResult>).where(
            (element) => (element.params[kPersonParamID] as String?) != null,
          ),
        );

    return searchFilter
        .take(2)
        .map((e) => e.params[kPersonParamID] as String)
        .toList();
  }

  Future<List<GenericSearchResult>> getLocationResults(
    BuildContext context,
    String query,
  ) async {
    final locationTagEntities = (await locationService.getLocationTags());
    final Map<LocalEntity<LocationTag>, List<EnteFile>> result = {};
    final normalizedQuery = query.toLowerCase();
    if (!context.mounted) return const [];
    final noLocationName = AppLocalizations.of(context).noLocation;
    if (!context.mounted) return const [];
    final noLocationTagName = AppLocalizations.of(context).noLocationTag;
    final normalizedNoLocationName = noLocationName.toLowerCase();
    final normalizedNoLocationTagName = noLocationTagName.toLowerCase();
    final disambiguationPrefixLength = min(
      normalizedNoLocationName.length,
      normalizedNoLocationTagName.length,
    );
    var sharedPrefixLength = 0;
    while (sharedPrefixLength < disambiguationPrefixLength &&
        normalizedNoLocationName.codeUnitAt(sharedPrefixLength) ==
            normalizedNoLocationTagName.codeUnitAt(sharedPrefixLength)) {
      sharedPrefixLength++;
    }
    final bool showNoLocation =
        normalizedQuery.length > 2 &&
        normalizedNoLocationName.startsWith(normalizedQuery);
    final bool showNoLocationTag =
        normalizedQuery.length > sharedPrefixLength &&
        normalizedNoLocationTagName.startsWith(normalizedQuery);

    final List<GenericSearchResult> searchResults = [];

    for (LocalEntity<LocationTag> tag in locationTagEntities) {
      if (tag.item.name.toLowerCase().contains(query.toLowerCase())) {
        result[tag] = [];
      }
    }
    final allFiles = await getAllFilesForSearch();
    for (EnteFile file in allFiles) {
      if (file.hasLocation) {
        for (LocalEntity<LocationTag> tag in result.keys) {
          if (isFileInsideLocationTag(
            tag.item.centerPoint,
            file.location!,
            tag.item.radius,
          )) {
            result[tag]!.add(file);
          }
        }
      }
    }
    if (showNoLocation) {
      final noLocationFiles = allFiles.where((file) {
        return file.isOwner && !file.hasLocation;
      }).toList();
      if (noLocationFiles.isNotEmpty) {
        searchResults.add(
          GenericSearchResult(
            ResultType.fileType,
            noLocationName,
            noLocationFiles,
            hierarchicalSearchFilter: TopLevelGenericFilter(
              filterName: noLocationName,
              occurrence: kMostRelevantFilter,
              filterResultType: ResultType.fileType,
              matchedUploadedIDs: filesToUploadedFileIDs(noLocationFiles),
              filterIcon: HugeIcons.strokeRoundedLocationOffline01,
            ),
          ),
        );
      }
    }
    if (showNoLocationTag) {
      _logger.info("finding photos with no location tag");
      // find files that have location but the file's location is not inside
      // any location tag
      final noLocationTagFiles = allFiles.where((file) {
        if (!file.hasLocation) {
          return false;
        }
        for (LocalEntity<LocationTag> tag in locationTagEntities) {
          if (isFileInsideLocationTag(
            tag.item.centerPoint,
            file.location!,
            tag.item.radius,
          )) {
            return false;
          }
        }
        return true;
      }).toList();
      if (noLocationTagFiles.isNotEmpty) {
        searchResults.add(
          GenericSearchResult(
            ResultType.fileType,
            noLocationTagName,
            noLocationTagFiles,
            hierarchicalSearchFilter: TopLevelGenericFilter(
              filterName: noLocationTagName,
              occurrence: kMostRelevantFilter,
              filterResultType: ResultType.fileType,
              matchedUploadedIDs: filesToUploadedFileIDs(noLocationTagFiles),
              filterIcon: HugeIcons.strokeRoundedLocationOffline01,
            ),
          ),
        );
      }
    }
    final locationTagNames = <String>{};
    for (MapEntry<LocalEntity<LocationTag>, List<EnteFile>> entry
        in result.entries) {
      if (entry.value.isNotEmpty) {
        final name = entry.key.item.name;
        locationTagNames.add(name);
        searchResults.add(
          GenericSearchResult(
            ResultType.location,
            name,
            entry.value,
            onResultTap: (ctx) {
              routeToPage(
                ctx,
                LocationScreenStateProvider(entry.key, const LocationScreen()),
              );
            },
            hierarchicalSearchFilter: LocationFilter(
              locationTag: entry.key.item,
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: filesToUploadedFileIDs(entry.value),
            ),
          ),
        );
      }
    }
    //todo: remove this later, this hack is for interval+external evaluation
    // for suggestions
    final allCitiesSearch = query == '__city';
    if (allCitiesSearch) {
      query = '';
    }
    final results = await locationService.getFilesInCity(allFiles, query);
    final List<City> sortedByResultCount = results.keys.toList()
      ..sort((a, b) => results[b]!.length.compareTo(results[a]!.length));
    for (final city in sortedByResultCount) {
      // If the location tag already exists for a city, don't add it again
      if (!locationTagNames.contains(city.city)) {
        final a =
            (defaultCityRadius * scaleFactor(city.lat)) / kilometersPerDegree;
        const b = defaultCityRadius / kilometersPerDegree;
        searchResults.add(
          GenericSearchResult(
            ResultType.location,
            city.city,
            results[city]!,
            hierarchicalSearchFilter: LocationFilter(
              locationTag: LocationTag(
                name: city.city,
                radius: defaultCityRadius,
                centerPoint: Location(latitude: city.lat, longitude: city.lng),
                aSquare: a * a,
                bSquare: b * b,
              ),
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: filesToUploadedFileIDs(results[city]!),
            ),
          ),
        );
      }
    }
    return searchResults;
  }

  Future<Map<String, List<EnteFile>>> getClusterFilesForPersonID(
    String personID,
  ) async {
    _logger.info('getClusterFilesForPersonID $personID');
    final Map<int, Set<String>> fileIdToClusterID = await mlDataDB
        .getFileIdToClusterIDSet(personID);
    _logger.info('faceDbDone getClusterFilesForPersonID $personID');
    final Map<String, List<EnteFile>> clusterIDToFiles = {};
    final allFiles = await getAllFilesForSearch();
    for (final f in allFiles) {
      if (!fileIdToClusterID.containsKey(f.uploadedFileID ?? -1)) {
        continue;
      }
      final cluserIds = fileIdToClusterID[f.uploadedFileID ?? -1]!;
      for (final cluster in cluserIds) {
        if (clusterIDToFiles.containsKey(cluster)) {
          clusterIDToFiles[cluster]!.add(f);
        } else {
          clusterIDToFiles[cluster] = [f];
        }
      }
    }
    _logger.info('done getClusterFilesForPersonID $personID');
    return clusterIDToFiles;
  }

  Future<List<EnteFile>> getFilesForPersonID(
    String personID, {
    bool includeManualAssigned = true,
    bool sortOnTime = true,
  }) async {
    final allFiles = await getAllFilesForSearch();
    final uploadedIdToFile = <int, EnteFile>{};
    for (final file in allFiles) {
      final uploadedID = file.uploadedFileID;
      if (uploadedID != null && !uploadedIdToFile.containsKey(uploadedID)) {
        uploadedIdToFile[uploadedID] = file;
      }
    }
    final Map<int, Set<String>> fileIdToClusterID = await mlDataDB
        .getFileIdToClusterIDSet(personID);
    final files = <EnteFile>[];
    final addedFileIDs = <int>{};

    for (final entry in fileIdToClusterID.entries) {
      final file = uploadedIdToFile[entry.key];
      if (file == null) {
        continue;
      }
      if (addedFileIDs.add(entry.key)) {
        files.add(file);
      }
    }
    if (includeManualAssigned) {
      final person = await PersonService.instance.getPerson(personID);
      if (person != null) {
        final manualIDs = person.data.manuallyAssigned.toSet();
        if (manualIDs.isNotEmpty) {
          for (final manualID in manualIDs) {
            if (addedFileIDs.contains(manualID)) {
              continue;
            }
            final file = uploadedIdToFile[manualID];
            if (file != null) {
              files.add(file);
              addedFileIDs.add(manualID);
            }
          }
        }
      }
    }
    if (sortOnTime) {
      files.sort(
        (a, b) => (b.creationTime ?? 0).compareTo(a.creationTime ?? 0),
      );
    }
    return files;
  }

  Future<List<GenericSearchResult>> getAllFace(
    int? limit, {
    required int minClusterSize,
    int? fallbackMinClusterSize,
    bool showIgnoredOnly = false,
    bool includeEmptyPersons = false,
  }) async {
    try {
      if (isLocalGalleryMode) {
        final effectiveMinClusterSize = minClusterSize > 1 ? 1 : minClusterSize;
        if (showIgnoredOnly) {
          return [];
        }
        debugPrint("getting faces (localGallery)");
        final localGalleryMlDb = MLDataDB.localGalleryInstance;
        final Map<int, Set<String>> fileIdToClusterID = await localGalleryMlDb
            .getFileIdToClusterIds();
        if (fileIdToClusterID.isEmpty) {
          return [];
        }
        final localIntIds = fileIdToClusterID.keys.toSet();
        final localIdMap = await OfflineFilesDB.instance.getLocalIdsForIntIds(
          localIntIds,
        );
        final allFiles = await getAllFilesForSearch();
        final localIdToFile = <String, EnteFile>{};
        for (final file in allFiles) {
          final localId = file.localID;
          if (localId != null && localId.isNotEmpty) {
            localIdToFile[localId] = file;
          }
        }
        final Map<String, List<EnteFile>> clusterIdToFiles = {};
        for (final entry in fileIdToClusterID.entries) {
          final localId = localIdMap[entry.key];
          if (localId == null) continue;
          final file = localIdToFile[localId];
          if (file == null) continue;
          for (final cluster in entry.value) {
            clusterIdToFiles.putIfAbsent(cluster, () => []).add(file);
          }
        }
        final List<GenericSearchResult> facesResult = [];
        final sortedClusterIds = clusterIdToFiles.keys.toList()
          ..sort(
            (a, b) => clusterIdToFiles[b]!.length.compareTo(
              clusterIdToFiles[a]!.length,
            ),
          );
        for (final clusterId in sortedClusterIds) {
          final files = clusterIdToFiles[clusterId]!;
          if (files.length < effectiveMinClusterSize) continue;
          facesResult.add(
            GenericSearchResult(
              ResultType.faces,
              "",
              files,
              params: {kClusterParamId: clusterId},
              onResultTap: (ctx) {
                routeToPage(
                  ctx,
                  ClusterPage(
                    files,
                    tagPrefix: "${ResultType.faces.toString()}_$clusterId",
                    clusterID: clusterId,
                    showNamingBanner: false,
                  ),
                );
              },
              hierarchicalSearchFilter: FaceFilter(
                personId: null,
                clusterId: clusterId,
                faceName: null,
                faceFile: files.first,
                occurrence: kMostRelevantFilter,
                matchedUploadedIDs: filesToUploadedFileIDs(files),
              ),
            ),
          );
        }
        if (facesResult.isEmpty) return [];
        sortPeopleFaces(
          facesResult,
          PeopleSortConfig(
            sortKey: localSettings.peopleSortKey(),
            nameSortAscending: localSettings.peopleNameSortAscending,
            updatedSortAscending: localSettings.peopleUpdatedSortAscending,
            photosSortAscending: localSettings.peoplePhotosSortAscending,
          ),
        );
        if (limit != null) {
          return facesResult.sublist(0, min(limit, facesResult.length));
        }
        return facesResult;
      }
      debugPrint("getting faces");
      final Map<int, Set<String>> fileIdToClusterID = await mlDataDB
          .getFileIdToClusterIds();
      final Map<String, PersonEntity> personIdToPerson = await PersonService
          .instance
          .getPersonsMap();
      final clusterIDToPersonID = await mlDataDB.getClusterIDToPersonID();

      final List<GenericSearchResult> facesResult = [];
      final Map<String, List<EnteFile>> clusterIdToFiles = {};
      final Map<String, List<EnteFile>> personIdToFiles = {};
      final Map<String, Set<int>> personIdToFileIds = {};
      final allFiles = await getAllFilesForSearch();
      final Map<int, EnteFile> uploadedIdToFile = {};
      for (final file in allFiles) {
        final uploadedID = file.uploadedFileID;
        if (uploadedID != null && !uploadedIdToFile.containsKey(uploadedID)) {
          uploadedIdToFile[uploadedID] = file;
        }
      }

      for (final entry in fileIdToClusterID.entries) {
        final file = uploadedIdToFile[entry.key];
        if (file == null) {
          continue;
        }
        final clusterIds = entry.value;
        for (final cluster in clusterIds) {
          final PersonEntity? p =
              personIdToPerson[clusterIDToPersonID[cluster] ?? ""];
          if (p != null) {
            final filesForPerson = personIdToFiles.putIfAbsent(
              p.remoteID,
              () => [],
            );
            filesForPerson.add(file);
            final fileIdsForPerson = personIdToFileIds.putIfAbsent(
              p.remoteID,
              () => <int>{},
            );
            fileIdsForPerson.add(entry.key);
          } else {
            if (clusterIdToFiles.containsKey(cluster)) {
              clusterIdToFiles[cluster]!.add(file);
            } else {
              clusterIdToFiles[cluster] = [file];
            }
          }
        }
      }

      for (final entry in personIdToPerson.entries) {
        final personID = entry.key;
        final manualIDs = entry.value.data.manuallyAssigned.toSet();
        if (manualIDs.isEmpty) continue;

        final filesForPerson = personIdToFiles.putIfAbsent(
          personID,
          () => <EnteFile>[],
        );
        final idSet = personIdToFileIds.putIfAbsent(personID, () => <int>{});

        for (final manualID in manualIDs) {
          if (idSet.contains(manualID)) {
            continue;
          }
          final file = uploadedIdToFile[manualID];
          if (file != null) {
            filesForPerson.add(file);
            idSet.add(manualID);
          }
        }
      }

      if (includeEmptyPersons) {
        for (final personID in personIdToPerson.keys) {
          personIdToFiles.putIfAbsent(personID, () => <EnteFile>[]);
          personIdToFileIds.putIfAbsent(personID, () => <int>{});
        }
      }

      // get sorted personId by files count
      final sortedPersonIds = personIdToFiles.keys.toList()
        ..sort(
          (a, b) =>
              personIdToFiles[b]!.length.compareTo(personIdToFiles[a]!.length),
        );
      final pinnedPersonIds = <String>[];
      final unpinnedPersonIds = <String>[];
      for (final personId in sortedPersonIds) {
        final person = personIdToPerson[personId];
        if (person != null && person.data.isPinned) {
          pinnedPersonIds.add(personId);
        } else {
          unpinnedPersonIds.add(personId);
        }
      }
      final orderedPersonIds = [...pinnedPersonIds, ...unpinnedPersonIds];
      for (final personID in orderedPersonIds) {
        final files = personIdToFiles[personID]!;
        final PersonEntity p = personIdToPerson[personID]!;
        final bool isIgnored = p.data.isIgnored;
        if (showIgnoredOnly != isIgnored) continue;
        if (!includeEmptyPersons && files.isEmpty) continue;
        final matchedUploadedIDs = personIdToFileIds[personID]!;
        final previewFile = files.isEmpty ? null : files.first;
        final params = {
          kPersonWidgetKey: p.data.avatarFaceID ?? p.hashCode.toString(),
          kPersonParamID: personID,
          if (previewFile != null) kFileID: previewFile.uploadedFileID,
          kPersonPinned: p.data.isPinned,
        };
        facesResult.add(
          GenericSearchResult(
            ResultType.faces,
            p.data.name,
            files,
            params: params,
            onResultTap: (ctx) {
              routeToPage(
                ctx,
                PeoplePage(
                  tagPrefix: "${ResultType.faces.toString()}_${p.data.name}",
                  person: p,
                  searchResult: GenericSearchResult(
                    ResultType.faces,
                    p.data.name,
                    files,
                    params: params,
                    hierarchicalSearchFilter: FaceFilter(
                      personId: p.remoteID,
                      clusterId: null,
                      faceName: p.data.name,
                      faceFile: previewFile,
                      occurrence: kMostRelevantFilter,
                      matchedUploadedIDs: matchedUploadedIDs,
                    ),
                  ),
                ),
              );
            },
            hierarchicalSearchFilter: FaceFilter(
              personId: p.remoteID,
              clusterId: null,
              faceName: p.data.name,
              faceFile: previewFile,
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: matchedUploadedIDs,
            ),
          ),
        );
      }
      final sortedClusterIds = clusterIdToFiles.keys.toList()
        ..sort(
          (a, b) => clusterIdToFiles[b]!.length.compareTo(
            clusterIdToFiles[a]!.length,
          ),
        );

      if (!showIgnoredOnly) {
        for (final clusterId in sortedClusterIds) {
          final files = clusterIdToFiles[clusterId]!;
          final String clusterName = clusterId;

          if (clusterIDToPersonID[clusterId] != null) {
            final String personID = clusterIDToPersonID[clusterId]!;
            final PersonEntity? p = personIdToPerson[personID];
            if (p != null) {
              // This should not be possible since it should be handled in the above loop, logging just in case
              _logger.severe(
                "`getAllFace`: Something unexpected happened, Cluster $clusterId should not have person id $personID",
                Exception(
                  'Some unexpected error occurred in getAllFace wrt cluster to person mapping',
                ),
              );
            } else {
              // This should not happen, means a clusterID is still assigned to a personID of a person that no longer exists
              // Logging the error and deleting the clusterID to personID mapping
              _logger.severe(
                "`getAllFace`: Cluster $clusterId should not have person id ${clusterIDToPersonID[clusterId]}, deleting the mapping",
                Exception(
                  'ClusterID assigned to a person that no longer exists',
                ),
              );
              await mlDataDB.removeClusterToPerson(
                personID: personID,
                clusterID: clusterId,
              );
            }
          }
          if (files.length < minClusterSize) continue;
          facesResult.add(
            GenericSearchResult(
              ResultType.faces,
              "",
              files,
              params: {
                kClusterParamId: clusterId,
                kFileID: files.first.uploadedFileID,
              },
              onResultTap: (ctx) {
                routeToPage(
                  ctx,
                  ClusterPage(
                    files,
                    tagPrefix: "${ResultType.faces.toString()}_$clusterName",
                    clusterID: clusterId,
                  ),
                );
              },
              hierarchicalSearchFilter: FaceFilter(
                personId: null,
                clusterId: clusterId,
                faceName: null,
                faceFile: files.first,
                occurrence: kMostRelevantFilter,
                matchedUploadedIDs: filesToUploadedFileIDs(files),
              ),
            ),
          );
        }
      }
      if (facesResult.isEmpty) {
        if (fallbackMinClusterSize != null &&
            fallbackMinClusterSize < minClusterSize) {
          return getAllFace(
            limit,
            minClusterSize: fallbackMinClusterSize,
            showIgnoredOnly: showIgnoredOnly,
            includeEmptyPersons: includeEmptyPersons,
          );
        } else {
          return [];
        }
      }
      sortPeopleFaces(
        facesResult,
        PeopleSortConfig(
          sortKey: localSettings.peopleSortKey(),
          nameSortAscending: localSettings.peopleNameSortAscending,
          updatedSortAscending: localSettings.peopleUpdatedSortAscending,
          photosSortAscending: localSettings.peoplePhotosSortAscending,
        ),
      );
      if (limit != null) {
        return facesResult.sublist(0, min(limit, facesResult.length));
      } else {
        return facesResult;
      }
    } catch (e, s) {
      _logger.severe("Error in getAllFace", e, s);
      rethrow;
    }
  }

  Future<List<GenericSearchResult>> getAllLocationTags(int? limit) async {
    try {
      final Map<LocalEntity<LocationTag>, List<EnteFile>> tagToItemsMap = {};
      final List<GenericSearchResult> tagSearchResults = [];
      final locationTagEntities = (await locationService.getLocationTags());
      final allFiles = await getAllFilesForSearch();
      final List<EnteFile> filesWithNoLocTag = [];

      for (int i = 0; i < locationTagEntities.length; i++) {
        if (limit != null && i >= limit) break;
        tagToItemsMap[locationTagEntities.elementAt(i)] = [];
      }

      for (EnteFile file in allFiles) {
        if (file.hasLocation) {
          bool hasLocationTag = false;
          for (LocalEntity<LocationTag> tag in tagToItemsMap.keys) {
            if (isFileInsideLocationTag(
              tag.item.centerPoint,
              file.location!,
              tag.item.radius,
            )) {
              hasLocationTag = true;
              tagToItemsMap[tag]!.add(file);
            }
          }
          // If the location tag already exists for a city, do not consider
          // it for the city suggestions
          if (!hasLocationTag) {
            filesWithNoLocTag.add(file);
          }
        }
      }

      for (MapEntry<LocalEntity<LocationTag>, List<EnteFile>> entry
          in tagToItemsMap.entries) {
        if (entry.value.isNotEmpty) {
          tagSearchResults.add(
            GenericSearchResult(
              ResultType.location,
              entry.key.item.name,
              entry.value,
              onResultTap: (ctx) {
                routeToPage(
                  ctx,
                  LocationScreenStateProvider(
                    entry.key,
                    LocationScreen(
                      //this is SearchResult.heroTag()
                      tagPrefix:
                          "${ResultType.location.toString()}_${entry.key.item.name}",
                    ),
                  ),
                );
              },
              hierarchicalSearchFilter: LocationFilter(
                locationTag: entry.key.item,
                occurrence: kMostRelevantFilter,
                matchedUploadedIDs: filesToUploadedFileIDs(entry.value),
              ),
            ),
          );
        }
      }
      // Add the found base locations from the location/memories service
      // TODO: lau: Add base location names
      // if (limit == null || tagSearchResults.length < limit) {
      //   for (final BaseLocation base in locationService.baseLocations) {
      //     final a = (baseRadius * scaleFactor(base.location.latitude!)) /
      //         kilometersPerDegree;
      //     const b = baseRadius / kilometersPerDegree;
      //     tagSearchResults.add(
      //       GenericSearchResult(
      //         ResultType.location,
      //         "Base",
      //         base.files,
      //         onResultTap: (ctx) {
      //           showAddLocationSheet(
      //             ctx,
      //             base.location,
      //             name: "Base",
      //             radius: baseRadius,
      //           );
      //         },
      //         hierarchicalSearchFilter: LocationFilter(
      //           locationTag: LocationTag(
      //             name: "Base",
      //             radius: baseRadius,
      //             centerPoint: base.location,
      //             aSquare: a * a,
      //             bSquare: b * b,
      //           ),
      //           occurrence: kMostRelevantFilter,
      //           matchedUploadedIDs: filesToUploadedFileIDs(base.files),
      //         ),
      //       ),
      //     );
      //   }
      // }

      if (limit == null || tagSearchResults.length < limit) {
        final results = await locationService.getFilesInCity(
          filesWithNoLocTag,
          '',
        );
        final List<City> sortedByResultCount = results.keys.toList()
          ..sort((a, b) => results[b]!.length.compareTo(results[a]!.length));
        for (final city in sortedByResultCount) {
          if (results[city]!.length <= 1) continue;
          final a =
              (defaultCityRadius * scaleFactor(city.lat)) / kilometersPerDegree;
          const b = defaultCityRadius / kilometersPerDegree;
          tagSearchResults.add(
            GenericSearchResult(
              ResultType.locationSuggestion,
              city.city,
              results[city]!,
              onResultTap: (ctx) {
                showAddLocationSheet(
                  ctx,
                  Location(latitude: city.lat, longitude: city.lng),
                  name: city.city,
                  radius: defaultCityRadius,
                );
              },
              hierarchicalSearchFilter: LocationFilter(
                locationTag: LocationTag(
                  name: city.city,
                  radius: defaultCityRadius,
                  centerPoint: Location(
                    latitude: city.lat,
                    longitude: city.lng,
                  ),
                  aSquare: a * a,
                  bSquare: b * b,
                ),
                occurrence: kMostRelevantFilter,
                matchedUploadedIDs: filesToUploadedFileIDs(results[city]!),
              ),
            ),
          );
        }
      }
      return tagSearchResults;
    } catch (e) {
      _logger.severe("Error in getAllLocationTags", e);
      return [];
    }
  }

  Future<List<GenericSearchResult>> getDateResults(
    BuildContext context,
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];

    final parsedDate = DateParseService.instance.parse(query);

    if (parsedDate.isEmpty) {
      return searchResults;
    }
    // Handle month-year queries
    if (parsedDate.day == null &&
        parsedDate.month != null &&
        parsedDate.year != null) {
      final month = parsedDate.month!;
      final year = parsedDate.year!;
      final monthYearFiles = await FilesDB.instance
          .getFilesCreatedWithinDurations(
            [_getDurationForMonthInYear(month, year)],
            ignoreCollections(),
            order: 'DESC',
          );
      if (monthYearFiles.isNotEmpty) {
        final monthName = DateParseService.instance.getMonthName(month);
        final name = '$monthName $year';
        searchResults.add(
          GenericSearchResult(
            ResultType.month,
            name,
            monthYearFiles,
            hierarchicalSearchFilter: TopLevelGenericFilter(
              filterName: name,
              occurrence: kMostRelevantFilter,
              filterResultType: ResultType.month,
              matchedUploadedIDs: filesToUploadedFileIDs(monthYearFiles),
              filterIcon: HugeIcons.strokeRoundedCalendar03,
            ),
          ),
        );
      }
    }
    // Handle day-month queries (with or without year)
    else if (parsedDate.day != null && parsedDate.month != null) {
      final int day = parsedDate.day!;
      final int month = parsedDate.month!;
      final int? year = parsedDate.year; // nullable for generic dates

      final matchedFiles = await FilesDB.instance
          .getFilesCreatedWithinDurations(
            _getDurationsForCalendarDateInEveryYear(day, month, year: year),
            ignoreCollections(),
            order: 'DESC',
          );

      if (matchedFiles.isNotEmpty) {
        final monthName = DateParseService.instance.getMonthName(month);
        final name = '$day $monthName${year != null ? ' $year' : ''}';
        searchResults.add(
          GenericSearchResult(
            ResultType.event,
            name,
            matchedFiles,
            hierarchicalSearchFilter: TopLevelGenericFilter(
              filterName: name,
              occurrence: kMostRelevantFilter,
              filterResultType: ResultType.event,
              matchedUploadedIDs: filesToUploadedFileIDs(matchedFiles),
              filterIcon: HugeIcons.strokeRoundedCalendar03,
            ),
          ),
        );
      }
    }
    return searchResults;
  }

  Future<List<GenericSearchResult>> getMagicSearchResults(
    BuildContext context,
    String query,
  ) async {
    final List<GenericSearchResult> searchResults = [];
    late List<EnteFile> files;
    late String resultForQuery;
    try {
      (resultForQuery, files) = await SemanticSearchService.instance
          .searchScreenQuery(query);
    } catch (e, s) {
      _logger.severe("Error occurred during magic search", e, s);
      return searchResults;
    }
    if (files.isNotEmpty && resultForQuery == query) {
      searchResults.add(
        GenericSearchResult(
          ResultType.magic,
          query,
          files,
          onResultTap: (context) {
            routeToPage(
              context,
              MagicResultScreen(
                files,
                name: query,
                enableGrouping: false,
                heroTag: GenericSearchResult(
                  ResultType.magic,
                  query,
                  files,
                  hierarchicalSearchFilter: MagicFilter(
                    filterName: query,
                    occurrence: kMostRelevantFilter,
                    matchedUploadedIDs: filesToUploadedFileIDs(files),
                  ),
                ).heroTag(),
                magicFilter: MagicFilter(
                  filterName: query,
                  occurrence: kMostRelevantFilter,
                  matchedUploadedIDs: filesToUploadedFileIDs(files),
                ),
              ),
            );
          },
          hierarchicalSearchFilter: MagicFilter(
            filterName: query,
            occurrence: kMostRelevantFilter,
            matchedUploadedIDs: filesToUploadedFileIDs(files),
          ),
        ),
      );
    }
    return searchResults;
  }

  /// For debug purposes only, don't use this in production!
  Future<List<GenericSearchResult>> smartMemories(
    BuildContext context,
    int? limit,
  ) async {
    DateTime calcTime = DateTime.now();
    late List<SmartMemory> memories;
    if (limit != null) {
      memories = await memoriesCacheService.getMemories();
    } else {
      // await two seconds to let new page load first
      await Future.delayed(const Duration(seconds: 1));
      if (!context.mounted) return const [];
      final DateTime? pickedTime = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(1900),
        lastDate: DateTime(2100),
      );
      if (pickedTime != null) calcTime = pickedTime;

      final cache = await memoriesCacheService.debugCacheForTesting();
      final memoriesResult = await smartMemoriesService.calcSmartMemories(
        calcTime,
        cache,
        debugSurfaceAll: true,
        mlEnabled:
            hasGrantedMLConsent && localSettings.isMLLocalIndexingEnabled,
      );
      locationService.baseLocations = memoriesResult.baseLocations;
      for (final nowMemory in memoriesResult.memories) {
        cache.toShowMemories.add(
          ToShowMemory.fromSmartMemory(nowMemory, calcTime),
        );
      }
      cache.baseLocations.addAll(memoriesResult.baseLocations);
      // memories = memoriesResult.memories;
      final tempCachePath =
          (await getTemporaryDirectory()).path +
          "/cache/test/memories_cache_test";
      await writeToJsonFile(
        tempCachePath,
        cache,
        MemoriesCache.encodeToJsonString,
      );
      _logger.info("Smart memories cache written to $tempCachePath");
      final decodedCache = await decodeJsonFile(
        tempCachePath,
        MemoriesCache.decodeFromJsonString,
      );
      _logger.info("Smart memories cache decoded from $tempCachePath");
      memories = await MemoriesCacheService.fromCacheToMemories(decodedCache!);
      _logger.info("Smart memories cache converted to memories");
    }
    final searchResults = <GenericSearchResult>[];
    for (final memory in memories) {
      final files = Memory.filesFromMemories(memory.memories);
      searchResults.add(
        GenericSearchResult(
          ResultType.event,
          memory.title + "(I)",
          files,
          hierarchicalSearchFilter: TopLevelGenericFilter(
            filterName: memory.title,
            occurrence: kMostRelevantFilter,
            filterResultType: ResultType.event,
            matchedUploadedIDs: filesToUploadedFileIDs(files),
            filterIcon: HugeIcons.strokeRoundedCalendar03,
          ),
        ),
      );
    }
    return searchResults;
  }

  Future<List<GenericSearchResult>> getContactSearchResults(
    String query,
  ) async {
    if (isLocalGalleryMode) {
      return <GenericSearchResult>[];
    }
    await _warmContactsCacheIfNeeded();
    final int ownerID = Configuration.instance.getUserID()!;
    final lowerCaseQuery = query.toLowerCase();
    final searchResults = <GenericSearchResult>[];
    final allFiles = await getAllFilesForSearch();
    final peopleToSharedFiles = <User, List<EnteFile>>{};
    final peopleToSharedAlbums = <String, List<Collection>>{};
    final existingEmails = <String>{};
    final List<Collection> collections = _collectionService.getCollectionsForUI(
      includedShared: true,
      includeCollab: true,
    );

    for (EnteFile file in allFiles) {
      if (file.isOwner) continue;

      final fileOwner = CollectionsService.instance.getFileOwner(
        file.ownerID!,
        file.collectionID,
      );

      if (matchesResolvedContactQuery(fileOwner, lowerCaseQuery)) {
        if (peopleToSharedFiles.containsKey(fileOwner)) {
          peopleToSharedFiles[fileOwner]!.add(file);
        } else {
          peopleToSharedFiles[fileOwner] = [file];
          existingEmails.add(fileOwner.email);
        }
      }
    }

    final relevantContacts = UserService.instance.getRelevantContacts();

    for (final user in relevantContacts) {
      if (existingEmails.contains(user.email)) {
        continue;
      }
      if (matchesResolvedContactQuery(user, lowerCaseQuery)) {
        peopleToSharedFiles[user] = [];
      }
    }

    for (Collection collection in collections) {
      if (collection.isHidden() || collection.isOwner(ownerID)) {
        continue;
      }

      if (peopleToSharedAlbums.containsKey(collection.owner.email)) {
        peopleToSharedAlbums[collection.owner.email]!.add(collection);
      } else {
        peopleToSharedAlbums[collection.owner.email] = [collection];
      }
    }

    for (final entry in peopleToSharedFiles.entries) {
      final user = entry.key;
      final files = entry.value;
      final collections = peopleToSharedAlbums[user.email] ?? [];
      final name = resolveDisplayName(user);
      final params = _contactSearchParams(user, collections);

      searchResults.add(
        GenericSearchResult(
          ResultType.shared,
          name,
          files,
          hierarchicalSearchFilter: ContactsFilter(
            user: user,
            occurrence: kMostRelevantFilter,
            matchedUploadedIDs: filesToUploadedFileIDs(files),
          ),
          params: params,
        ),
      );
    }

    return searchResults;
  }

  Future<List<GenericSearchResult>> getAllContactsSearchResults(
    int? limit,
  ) async {
    try {
      await _warmContactsCacheIfNeeded();
      final int ownerID = Configuration.instance.getUserID()!;
      final searchResults = <GenericSearchResult>[];
      final allFiles = await getAllFilesForSearch();
      final peopleToSharedFiles = <User, List<EnteFile>>{};
      final peopleToSharedAlbums = <String, List<Collection>>{};
      final existingEmails = <String>{};
      final List<Collection> collections = _collectionService
          .getCollectionsForUI(includedShared: true, includeCollab: true);

      for (Collection collection in collections) {
        if (collection.isHidden() ||
            collection.isArchived() ||
            collection.isOwner(ownerID)) {
          continue;
        }

        if (peopleToSharedAlbums.containsKey(collection.owner.email)) {
          peopleToSharedAlbums[collection.owner.email]!.add(collection);
        } else {
          peopleToSharedAlbums[collection.owner.email] = [collection];
        }
      }

      for (EnteFile file in allFiles) {
        if (file.isOwner) continue;

        final fileOwner = CollectionsService.instance.getFileOwner(
          file.ownerID!,
          file.collectionID,
        );
        if (peopleToSharedFiles.containsKey(fileOwner)) {
          peopleToSharedFiles[fileOwner]!.add(file);
        } else {
          peopleToSharedFiles[fileOwner] = [file];
          existingEmails.add(fileOwner.email);
        }
      }

      final allRelevantContacts = UserService.instance.getRelevantContacts();

      for (final user in allRelevantContacts) {
        if (existingEmails.contains(user.email)) {
          continue;
        }
        peopleToSharedFiles[user] = [];
      }

      final sortedEntries = peopleToSharedFiles.entries.toList();
      sortedEntries.sort((a, b) {
        final countComparison = b.value.length.compareTo(a.value.length);
        if (countComparison != 0) {
          return countComparison;
        }

        final aName =
            a.key.displayName?.toLowerCase() ?? a.key.email.toLowerCase();
        final bName =
            b.key.displayName?.toLowerCase() ?? b.key.email.toLowerCase();
        return aName.compareTo(bName);
      });

      final limitedEntries = limit != null
          ? _preserveEmailOnlyContactsWithinLimit(sortedEntries, limit)
          : sortedEntries;

      for (var entry in limitedEntries) {
        final user = entry.key;
        final files = entry.value;
        final name = resolveDisplayName(user);
        final collections = peopleToSharedAlbums[user.email] ?? [];
        final params = _contactSearchParams(user, collections);
        searchResults.add(
          GenericSearchResult(
            ResultType.shared,
            name,
            files,
            hierarchicalSearchFilter: ContactsFilter(
              user: user,
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: filesToUploadedFileIDs(files),
            ),
            params: params,
          ),
        );
      }

      return searchResults;
    } catch (e) {
      _logger.severe("Error in getAllContactSearchResults", e);
      return [];
    }
  }

  List<MonthData> _getMatchingMonths(BuildContext context, String query) {
    return getMonthData(context)
        .where(
          (monthData) =>
              monthData.name.toLowerCase().startsWith(query.toLowerCase()),
        )
        .toList();
  }

  List<MapEntry<User, List<EnteFile>>> _preserveEmailOnlyContactsWithinLimit(
    List<MapEntry<User, List<EnteFile>>> sortedEntries,
    int limit,
  ) {
    if (limit <= 0) {
      return const [];
    }
    final limitedEntries = sortedEntries.take(limit).toList();
    if (limitedEntries.length < limit ||
        limitedEntries.any((entry) => entry.key.id == null)) {
      return limitedEntries;
    }

    final includedEmails = limitedEntries
        .map((entry) => entry.key.email)
        .toSet();
    MapEntry<User, List<EnteFile>>? overflowEmailOnly;
    for (final entry in sortedEntries.skip(limit)) {
      if (entry.key.id == null && !includedEmails.contains(entry.key.email)) {
        overflowEmailOnly = entry;
        break;
      }
    }
    if (overflowEmailOnly == null) {
      return limitedEntries;
    }

    limitedEntries[limitedEntries.length - 1] = overflowEmailOnly;
    return limitedEntries;
  }

  Future<List<EnteFile>> _getFilesInYear(List<int> durationOfYear) async {
    return await FilesDB.instance.getFilesCreatedWithinDurations(
      [durationOfYear],
      ignoreCollections(),
      order: "DESC",
    );
  }

  List<List<int>> _getDurationsForCalendarDateInEveryYear(
    int day,
    int month, {
    int? year,
  }) {
    final List<List<int>> durationsOfHolidayInEveryYear = [];
    final int startYear = year ?? searchStartYear;
    final int endYear = year ?? currentYear;
    for (var yr = startYear; yr <= endYear; yr++) {
      if (isValidGregorianDate(day: day, month: month, year: yr)) {
        durationsOfHolidayInEveryYear.add([
          DateTime(yr, month, day).microsecondsSinceEpoch,
          DateTime(yr, month, day + 1).microsecondsSinceEpoch,
        ]);
      }
    }
    return durationsOfHolidayInEveryYear;
  }

  List<List<int>> _getDurationsOfMonthInEveryYear(int month) {
    final List<List<int>> durationsOfMonthInEveryYear = [];
    for (var year = searchStartYear; year <= currentYear; year++) {
      durationsOfMonthInEveryYear.add([
        DateTime.utc(year, month, 1).microsecondsSinceEpoch,
        month == 12
            ? DateTime(year + 1, 1, 1).microsecondsSinceEpoch
            : DateTime(year, month + 1, 1).microsecondsSinceEpoch,
      ]);
    }
    return durationsOfMonthInEveryYear;
  }

  List<int> _getDurationForMonthInYear(int month, int year) {
    return [
      DateTime(year, month, 1).microsecondsSinceEpoch,
      month == 12
          ? DateTime(year + 1, 1, 1).microsecondsSinceEpoch
          : DateTime(year, month + 1, 1).microsecondsSinceEpoch,
    ];
  }
}
