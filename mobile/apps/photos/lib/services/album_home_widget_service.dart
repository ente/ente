import "dart:async";
import 'dart:convert';
import "dart:math";

import "package:collection/collection.dart";
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/app_navigation_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/favorites_service.dart';
import 'package:photos/services/home_widget_service.dart';
import 'package:photos/services/search_service.dart';
import 'package:photos/services/sync/local_sync_service.dart';
import "package:photos/ui/viewer/file/detail_page.dart";
import 'package:photos/ui/viewer/gallery/collection_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _AlbumWidgetCacheUpdateReason { none, changed, stale }

class AlbumHomeWidgetService {
  // Constants
  static const String SELECTED_ALBUMS_KEY = "selectedAlbumsHW";
  static const String ALBUMS_LAST_HASH_KEY = "albumsLastHash";
  static const String ANDROID_CLASS_NAME = "EnteAlbumsWidgetProvider";
  static const String IOS_CLASS_NAME = "EnteAlbumWidget";
  static const String ALBUMS_CHANGED_KEY = "albumsChanged.widget";
  static const String ALBUMS_STATUS_KEY = "albumsStatusKey.widget";
  static const String ALBUMS_LAST_CACHE_REFRESH_TIME_KEY =
      "albumsLastCacheRefreshTime";
  static const String TOTAL_ALBUMS_KEY = "totalAlbums";
  static const int MAX_ALBUMS_LIMIT = 50;
  static const Duration ALBUMS_CACHE_REFRESH_INTERVAL = Duration(hours: 24);

  // Singleton pattern
  static final AlbumHomeWidgetService instance =
      AlbumHomeWidgetService._privateConstructor();
  AlbumHomeWidgetService._privateConstructor() {
    _listenToLocalPhotoUpdates();
  }

  // Properties
  final Logger _logger = Logger((AlbumHomeWidgetService).toString());
  SharedPreferences get _prefs => ServiceLocator.instance.prefs;

  void _listenToLocalPhotoUpdates() {
    Bus.instance.on<LocalPhotosUpdatedEvent>().listen((event) async {
      if (event.type != EventType.hide ||
          isLocalGalleryMode ||
          !Configuration.instance.hasConfiguredAccount()) {
        return;
      }

      final hiddenUploadedIDs = event.updatedFiles
          .map((file) => file.uploadedFileID)
          .whereType<int>()
          .toSet();
      if (hiddenUploadedIDs.isEmpty) {
        return;
      }

      if (!await _hasCachedHiddenWidgetFile(hiddenUploadedIDs)) {
        return;
      }

      _logger.info(
        "Hidden file intersects with album widget cache, recomputing widget",
      );
      await setSelectionChange(true);
      await initAlbumHomeWidget(false);
    });
  }

  // Public methods
  List<int>? getSelectedAlbumIds() {
    final selectedAlbums = _prefs.getStringList(SELECTED_ALBUMS_KEY);
    return selectedAlbums?.map((id) => int.tryParse(id) ?? 0).toList();
  }

  Future<void> updateSelectedAlbums(List<String> selectedAlbums) async {
    await _prefs.setStringList(SELECTED_ALBUMS_KEY, selectedAlbums);
    unawaited(_refreshOnSelection());
  }

  String? getAlbumsLastHash() {
    return _prefs.getString(ALBUMS_LAST_HASH_KEY);
  }

  Future<void> setAlbumsLastHash(String hash) async {
    await _prefs.setString(ALBUMS_LAST_HASH_KEY, hash);
  }

  Future<void> initAlbumHomeWidget(bool isBg) async {
    await HomeWidgetService.instance.computeLock.synchronized(() async {
      if (await _hasAnyBlockers(isBg)) {
        await clearWidget();
        return;
      }

      _logger.info("Initializing albums widget");

      final cacheUpdateReason = await _getWidgetCacheUpdateReason();

      if (cacheUpdateReason != _AlbumWidgetCacheUpdateReason.none) {
        await _updateAlbumsWidgetCache(
          isStaleRefresh:
              cacheUpdateReason == _AlbumWidgetCacheUpdateReason.stale,
        );
        await setSelectionChange(false);
        _logger.info("Force fetch new albums complete");
      } else {
        await _refreshAlbumsWidget();
        _logger.info("Refresh albums widget complete");
      }
    });
  }

  Future<void> clearWidget() async {
    if (getAlbumsStatus() == WidgetStatus.syncedEmpty) {
      return;
    }

    await setAlbumsLastHash("");
    await _clearAlbumsLastCacheRefreshTime();
    await _setTotalAlbums(null);
    await updateAlbumsStatus(WidgetStatus.syncedEmpty);
    await _refreshWidget(message: "AlbumsHomeWidget cleared & updated");
  }

  bool? hasSelectionChanged() {
    return _prefs.getBool(ALBUMS_CHANGED_KEY);
  }

  Future<void> setSelectionChange(bool value) async {
    _logger.info("Updating albums changed flag to $value");
    await _prefs.setBool(ALBUMS_CHANGED_KEY, value);
  }

  WidgetStatus getAlbumsStatus() {
    return WidgetStatus.values.firstWhereOrNull(
          (v) => v.index == (_prefs.getInt(ALBUMS_STATUS_KEY) ?? 0),
        ) ??
        WidgetStatus.notSynced;
  }

  Future<void> updateAlbumsStatus(WidgetStatus value) async {
    await _prefs.setInt(ALBUMS_STATUS_KEY, value.index);
  }

  Future<int> countHomeWidgets() async {
    return await HomeWidgetService.instance.countHomeWidgets(
      ANDROID_CLASS_NAME,
      IOS_CLASS_NAME,
    );
  }

  Future<void> checkPendingAlbumsSync() async {
    if (await _hasAnyBlockers()) {
      await clearWidget();
      return;
    }

    _logger.info("Checking pending albums sync");
    if (await _shouldUpdateWidgetCache()) {
      await initAlbumHomeWidget(false);
    }
  }

  Future<void> _refreshOnSelection() async {
    final lastHash = getAlbumsLastHash();
    final selectedAlbumIds = await _getEffectiveSelectedAlbumIds(false);
    final currentHash = _calculateHash(selectedAlbumIds);
    if (lastHash != null && currentHash == lastHash) {
      _logger.info("No changes detected in albums");
      return;
    }

    await setSelectionChange(true);
    await initAlbumHomeWidget(false);
  }

  List<Collection> getAlbumsByIds(List<int> albumIds) {
    final albums = <Collection>[];

    for (final albumId in albumIds) {
      final collection = CollectionsService.instance.getCollectionByID(albumId);
      if (collection != null &&
          !collection.isDeleted &&
          !collection.isHidden()) {
        albums.add(collection);
      }
    }

    return albums;
  }

  Future<void> onLaunchFromWidget(int fileId, int collectionId) async {
    final collection = CollectionsService.instance.getCollectionByID(
      collectionId,
    );
    if (collection == null) {
      _logger.warning(
        "Cannot launch widget: collection with ID $collectionId not found",
      );
      return;
    }

    // First navigate to the collection page
    final thumbnail = await CollectionsService.instance.getCover(collection);
    AppNavigationService.instance
        .pushPage(
          CollectionPage(CollectionWithThumbnail(collection, thumbnail)),
        )
        .ignore();
    final getAllFilesCollection = await FilesDB.instance.getAllFilesCollection(
      collection.id,
    );

    // Then open the specific file
    final file = await FilesDB.instance.getFile(fileId);
    if (file == null) {
      _logger.warning("Cannot launch widget: file with ID $fileId not found");
      return;
    }

    AppNavigationService.instance
        .pushPage(
          DetailPage(
            DetailPageConfiguration(
              getAllFilesCollection,
              getAllFilesCollection.indexOf(file),
              "albumwidget",
            ),
          ),
          forceCustomPageRoute: true,
        )
        .ignore();
    await _refreshAlbumsWidget();
  }

  // Private methods
  String _calculateHash(List<int> albumIds) {
    String updationTimestamps = "";

    // TODO: This can be done in one shot by querying the database directly
    for (final albumId in albumIds) {
      final collection = CollectionsService.instance.getCollectionByID(albumId);
      if (collection != null) {
        updationTimestamps += "$albumId:${collection.updationTime.toString()}_";
      }
    }

    if (updationTimestamps.isEmpty) return "";

    final hash = md5
        .convert(utf8.encode(updationTimestamps))
        .toString()
        .substring(0, 10);
    return hash;
  }

  Future<bool> _hasAnyBlockers([bool isBg = false]) async {
    // Check if first import is completed
    final hasCompletedFirstImport = LocalSyncService.instance
        .hasCompletedFirstImportOrBypassed();
    if (!hasCompletedFirstImport) {
      return true;
    }

    // Check if selected albums exist
    final selectedAlbumIds = await _getEffectiveSelectedAlbumIds(isBg);
    final albums = getAlbumsByIds(selectedAlbumIds);

    if (albums.isEmpty) {
      _logger.info("Selected albums are empty or do not exist");
      return true;
    }

    return false;
  }

  Future<bool> _hasCachedHiddenWidgetFile(Set<int> hiddenUploadedIDs) async {
    if (await countHomeWidgets() == 0 ||
        getAlbumsStatus() == WidgetStatus.syncedEmpty) {
      return false;
    }

    final totalAlbums = await HomeWidgetService.instance.getData<int>(
      TOTAL_ALBUMS_KEY,
    );
    if (totalAlbums == null || totalAlbums < 0) {
      return false;
    }

    bool foundLegacyMetadata = false;
    for (int index = 0; index < totalAlbums; index++) {
      final metadata = await _getWidgetEntryMetadata(index);
      if (metadata == null) {
        continue;
      }

      if (!metadata.containsKey(HomeWidgetService.UPLOADED_FILE_ID_KEY)) {
        foundLegacyMetadata = true;
        continue;
      }

      final rawUploadedFileID =
          metadata[HomeWidgetService.UPLOADED_FILE_ID_KEY];
      final uploadedFileID = rawUploadedFileID is num
          ? rawUploadedFileID.toInt()
          : null;
      if (uploadedFileID != null &&
          hiddenUploadedIDs.contains(uploadedFileID)) {
        return true;
      }
    }

    return foundLegacyMetadata;
  }

  Future<Map<String, dynamic>?> _getWidgetEntryMetadata(int index) async {
    final data = await HomeWidgetService.instance.getData<dynamic>(
      "albums_widget_$index${HomeWidgetService.DATA_SUFFIX}",
    );
    if (data == null) {
      return null;
    }

    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  Future<void> _refreshAlbumsWidget() async {
    // only refresh if widget was synced without issues
    if (await countHomeWidgets() == 0) return;
    await _refreshWidget(message: "Refreshing from existing album set");
  }

  Future<bool> _shouldUpdateWidgetCache() async {
    return await _getWidgetCacheUpdateReason() !=
        _AlbumWidgetCacheUpdateReason.none;
  }

  Future<_AlbumWidgetCacheUpdateReason> _getWidgetCacheUpdateReason() async {
    // Check if albums changed flag is set
    if (hasSelectionChanged() == true) {
      return _AlbumWidgetCacheUpdateReason.changed;
    }

    // Check if we have any albums selected
    final selectedAlbumIds = await _getEffectiveSelectedAlbumIds();
    if (selectedAlbumIds.isEmpty) {
      return _AlbumWidgetCacheUpdateReason.none;
    }

    // Check if hash has changed
    final currentHash = _calculateHash(selectedAlbumIds);
    final lastHash = getAlbumsLastHash();

    if (currentHash == lastHash) {
      final saveStatus = getAlbumsStatus();
      switch (saveStatus) {
        case WidgetStatus.syncedPartially:
          return await countHomeWidgets() > 0
              ? _AlbumWidgetCacheUpdateReason.changed
              : _AlbumWidgetCacheUpdateReason.none;
        case WidgetStatus.syncedAll:
          return await _shouldRefreshStaleWidgetCache()
              ? _AlbumWidgetCacheUpdateReason.stale
              : _AlbumWidgetCacheUpdateReason.none;
        case WidgetStatus.syncedEmpty:
          return _AlbumWidgetCacheUpdateReason.none;
        default:
      }
    }

    return _AlbumWidgetCacheUpdateReason.changed;
  }

  Future<bool> _shouldRefreshStaleWidgetCache() async {
    if (await countHomeWidgets() == 0) {
      return false;
    }

    final lastRefreshTime = _prefs.getInt(ALBUMS_LAST_CACHE_REFRESH_TIME_KEY);
    if (lastRefreshTime == null || lastRefreshTime <= 0) {
      return true;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastRefreshTime > now) {
      return false;
    }

    return now - lastRefreshTime >=
        ALBUMS_CACHE_REFRESH_INTERVAL.inMilliseconds;
  }

  Future<void> _setAlbumsLastCacheRefreshTime() async {
    await _prefs.setInt(
      ALBUMS_LAST_CACHE_REFRESH_TIME_KEY,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _clearAlbumsLastCacheRefreshTime() async {
    await _prefs.remove(ALBUMS_LAST_CACHE_REFRESH_TIME_KEY);
  }

  Future<List<int>> _getEffectiveSelectedAlbumIds([bool isBg = false]) async {
    final selectedAlbumIds = getSelectedAlbumIds();

    // If no albums selected, use favorites as default
    if (selectedAlbumIds == null || selectedAlbumIds.isEmpty) {
      if (isBg) {
        await FavoritesService.instance.initFav();
      }
      final favoriteId = await FavoritesService.instance
          .getFavoriteCollectionID();
      if (favoriteId != null) {
        await updateSelectedAlbums([favoriteId.toString()]);
        return [favoriteId];
      }
    }

    return selectedAlbumIds ?? [];
  }

  Future<void> _refreshWidget({String? message}) async {
    await HomeWidgetService.instance.updateWidget(
      androidClass: ANDROID_CLASS_NAME,
      iOSClass: IOS_CLASS_NAME,
    );

    if (flagService.internalUser) {
      await Fluttertoast.showToast(
        msg: "[i][al] ${message ?? "AlbumsHomeWidget updated"}",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.black,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }

    _logger.info("Home Widget updated: ${message ?? "standard update"}");
  }

  Future<Map<int, (String, Iterable<EnteFile>)>> _getAlbumsWithFiles() async {
    final selectedAlbumIds = await _getEffectiveSelectedAlbumIds();
    final albumsWithFiles = <int, (String, List<EnteFile>)>{};

    final hiddenFiles = await SearchService.instance.getHiddenFiles();
    final hiddenUploadIDs = <int>{};
    for (final file in hiddenFiles) {
      final uploadedID = file.uploadedFileID;
      if (uploadedID != null) {
        hiddenUploadIDs.add(uploadedID);
      }
    }

    for (final albumId in selectedAlbumIds) {
      final collection = CollectionsService.instance.getCollectionByID(albumId);
      if (collection != null) {
        final allFiles = await FilesDB.instance.getAllFilesCollection(
          collection.id,
        );
        final files = allFiles.where((file) {
          final uploadedID = file.uploadedFileID;
          return uploadedID == null || !hiddenUploadIDs.contains(uploadedID);
        }).toList();
        if (files.isNotEmpty) {
          albumsWithFiles[collection.id] = (
            collection.decryptedName ?? "Album",
            files,
          );
        }
      }
    }

    return albumsWithFiles;
  }

  Future<void> _setTotalAlbums(int? total) async {
    await HomeWidgetService.instance.setData(TOTAL_ALBUMS_KEY, total);
  }

  Future<void> _updateAlbumsWidgetCache({bool isStaleRefresh = false}) async {
    final selectedAlbumIds = await _getEffectiveSelectedAlbumIds();
    final albumsWithFiles = await _getAlbumsWithFiles();

    if (albumsWithFiles.isEmpty) {
      await clearWidget();
      return;
    }

    final bool isWidgetPresent = await countHomeWidgets() > 0;

    final limit = isWidgetPresent
        ? HomeWidgetService.instance.getWidgetImageLimit()
        : HomeWidgetService.WIDGET_IMAGE_LIMIT_MINIMAL;

    final Set<String> uniqueRenderableItems = <String>{};
    for (final entry in albumsWithFiles.entries) {
      for (final file in entry.value.$2) {
        if (file.generatedID != null) {
          uniqueRenderableItems.add('${entry.key}_${file.generatedID}');
        }
      }
    }

    final int renderTarget = uniqueRenderableItems.isEmpty
        ? 0
        : min(limit, uniqueRenderableItems.length);

    if (renderTarget == 0) {
      _logger.warning(
        "No unique files available for widget rendering (limit=$limit)",
      );
      await clearWidget();
      return;
    }

    final maxAttempts = renderTarget * 10;

    int renderedCount = 0;
    int attemptsCount = 0;

    await updateAlbumsStatus(WidgetStatus.notSynced);

    final albumsWithFilesLength = albumsWithFiles.length;
    final albumsWithFilesEntries = albumsWithFiles.entries.toList();
    final random = Random();

    final Set<String> renderedKeys = <String>{};
    final Set<String> failedKeys = <String>{};

    while (renderedCount < renderTarget && attemptsCount < maxAttempts) {
      final randomEntry =
          albumsWithFilesEntries[random.nextInt(albumsWithFilesLength)];

      if (randomEntry.value.$2.isEmpty) continue;

      final randomAlbumFile = randomEntry.value.$2.elementAt(
        random.nextInt(randomEntry.value.$2.length),
      );
      if (randomAlbumFile.generatedID == null) {
        attemptsCount++;
        continue;
      }
      final albumId = randomEntry.key;
      final albumName = randomEntry.value.$1;

      final String renderKey = '${albumId}_${randomAlbumFile.generatedID}';
      // Skip if already rendered or previously failed
      if (!renderedKeys.add(renderKey) || failedKeys.contains(renderKey)) {
        attemptsCount++;
        continue;
      }

      final renderResult = await HomeWidgetService.instance
          .renderFile(
            randomAlbumFile,
            "albums_widget_$renderedCount",
            albumName,
            albumId.toString(),
            uploadedFileID: randomAlbumFile.uploadedFileID,
          )
          .catchError((e, stackTrace) {
            _logger.severe("Error rendering widget", e, stackTrace);
            return null;
          });

      if (renderResult != null) {
        // Check for blockers again before continuing
        if (await _hasAnyBlockers()) {
          await clearWidget();
          return;
        }

        renderedCount++;
        await _setTotalAlbums(renderedCount);

        // Show update toast after first item is rendered
        if (renderedCount == 1) {
          await _refreshWidget(message: "First album fetched, updating widget");
          await updateAlbumsStatus(WidgetStatus.syncedPartially);
        }

        attemptsCount++;
      } else {
        // Track failed renders to avoid retrying known-bad files
        renderedKeys.remove(renderKey);
        failedKeys.add(renderKey);
        attemptsCount++;
      }
    }

    if (attemptsCount >= maxAttempts) {
      _logger.warning(
        "Hit max attempts $maxAttempts. Only rendered $renderedCount of target $renderTarget.",
      );
    }

    // Update the hash to track changes
    final hash = _calculateHash(selectedAlbumIds);
    await setAlbumsLastHash(hash);

    if (renderedCount == 0) {
      if (isStaleRefresh) {
        await _setAlbumsLastCacheRefreshTime();
        await updateAlbumsStatus(WidgetStatus.syncedAll);
      }
      return;
    }

    await _setAlbumsLastCacheRefreshTime();

    if (isWidgetPresent) {
      await updateAlbumsStatus(WidgetStatus.syncedAll);
    }

    await _refreshWidget(
      message: "Switched to next albums set, total: $renderedCount",
    );
  }
}
