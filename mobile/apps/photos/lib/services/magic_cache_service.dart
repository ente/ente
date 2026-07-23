import "dart:async";
import "dart:convert";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/file_uploaded_event.dart";
import "package:photos/events/magic_cache_updated_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/discover/prompt.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/magic_filter.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/module/upload/service/file_uploader.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/search/result/magic_result_screen.dart";
import "package:photos/utils/cache_util.dart";
import "package:shared_preferences/shared_preferences.dart";

class MagicCache {
  final String title;
  final List<int> fileUploadedIDs;
  final List<int>? fileLocalIntIDs;
  Map<int, int>? _fileIdToPositionMap;

  MagicCache(this.title, this.fileUploadedIDs, {this.fileLocalIntIDs});

  // Get map of uploadID to index in fileUploadedIDs
  Map<int, int> get fileIdToPositionMap {
    if (_fileIdToPositionMap == null) {
      _fileIdToPositionMap = {};
      final ids = fileLocalIntIDs ?? fileUploadedIDs;
      for (int i = 0; i < ids.length; i++) {
        _fileIdToPositionMap![ids[i]] = i;
      }
    }
    return _fileIdToPositionMap!;
  }

  factory MagicCache.fromJson(Map<String, dynamic> json) {
    return MagicCache(
      json['title'],
      List<int>.from(json['fileUploadedIDs']),
      fileLocalIntIDs: json['fileLocalIntIDs'] != null
          ? List<int>.from(json['fileLocalIntIDs'])
          : null,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'fileUploadedIDs': fileUploadedIDs.toList(),
      if (fileLocalIntIDs != null) 'fileLocalIntIDs': fileLocalIntIDs!.toList(),
    };
  }

  static String encodeListToJson(List<MagicCache> magicCaches) {
    final jsonList = magicCaches.map((cache) => cache.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static List<MagicCache> decodeJsonToList(String jsonString) {
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => MagicCache.fromJson(json)).toList();
  }
}

String getLocalizedTitle(BuildContext context, String title) {
  return getLocalizedTitleForL10n(context.l10n, title);
}

String getLocalizedTitleForL10n(AppLocalizations l10n, String title) {
  switch (title) {
    case 'Identity':
      return l10n.discover_identity;
    case 'Screenshots':
      return l10n.discover_screenshots;
    case 'QR Codes':
      return l10n.discover_qr_codes;
    case 'Receipts':
      return l10n.discover_receipts;
    case 'Notes':
      return l10n.discover_notes;
    case 'Memes':
      return l10n.discover_memes;
    case 'Visiting Cards':
      return l10n.discover_visiting_cards;
    case 'Babies':
      return l10n.discover_babies;
    case 'Pets':
      return l10n.discover_pets;
    case 'Selfies':
      return l10n.discover_selfies;
    case 'Wallpapers':
      return l10n.discover_wallpapers;
    case 'Food':
      return l10n.discover_food;
    case 'Celebrations':
      return l10n.discover_celebrations;
    case 'Sunset':
      return l10n.discover_sunset;
    case 'Hills':
      return l10n.discover_hills;
    case 'Greenery':
      return l10n.discover_greenery;
    default:
      return title; // If no match, return the original string
  }
}

int? _magicFileId(EnteFile file) {
  return file.uploadedFileID ?? file.generatedID;
}

int _compareLocalGalleryMagicFilesByRelevantPosition(
  EnteFile a,
  EnteFile b,
  Map<int, int> fileIdToPositionMap,
  Map<String, int> localIdToIntId,
) {
  final idA = localIdToIntId[a.localID];
  final idB = localIdToIntId[b.localID];
  final posA = idA != null ? fileIdToPositionMap[idA] : null;
  final posB = idB != null ? fileIdToPositionMap[idB] : null;
  if (posA == null && posB == null) return 0;
  if (posA == null) return 1;
  if (posB == null) return -1;
  return posA.compareTo(posB);
}

void sortLocalGalleryMagicFilesByCreationTime(
  List<EnteFile> files,
  Map<int, int> fileIdToPositionMap,
  Map<String, int> localIdToIntId,
) {
  files.sort((a, b) {
    final timeCompare = (b.creationTime ?? 0).compareTo(a.creationTime ?? 0);
    if (timeCompare != 0) {
      return timeCompare;
    }
    return _compareLocalGalleryMagicFilesByRelevantPosition(
      a,
      b,
      fileIdToPositionMap,
      localIdToIntId,
    );
  });
}

GenericSearchResult? toGenericSearchResult(
  BuildContext context,
  Prompt prompt,
  List<EnteFile> enteFilesInMagicCache,
  Map<int, int> fileIdToPositionMap, {
  Map<String, int>? localIdToIntId,
}) {
  if (enteFilesInMagicCache.isEmpty) {
    return null;
  }
  if (!prompt.recentFirst) {
    enteFilesInMagicCache.sort((a, b) {
      final idA = localIdToIntId != null
          ? localIdToIntId[a.localID]
          : _magicFileId(a);
      final idB = localIdToIntId != null
          ? localIdToIntId[b.localID]
          : _magicFileId(b);
      final posA = idA != null ? fileIdToPositionMap[idA] : null;
      final posB = idB != null ? fileIdToPositionMap[idB] : null;
      if (posA == null && posB == null) return 0;
      if (posA == null) return 1;
      if (posB == null) return -1;
      return posA.compareTo(posB);
    });
  }
  final String title = getLocalizedTitle(context, prompt.title);
  return GenericSearchResult(
    ResultType.magic,
    title,
    enteFilesInMagicCache,
    params: {
      "enableGrouping": prompt.recentFirst,
      "fileIdToPosMap": fileIdToPositionMap,
    },
    onResultTap: (ctx) {
      routeToPage(
        ctx,
        MagicResultScreen(
          enteFilesInMagicCache,
          name: title,
          enableGrouping: prompt.recentFirst,
          fileIdToPosMap: fileIdToPositionMap,
          heroTag: GenericSearchResult(
            ResultType.magic,
            title,
            enteFilesInMagicCache,
            hierarchicalSearchFilter: MagicFilter(
              filterName: title,
              occurrence: kMostRelevantFilter,
              matchedUploadedIDs: filesToUploadedFileIDs(enteFilesInMagicCache),
            ),
          ).heroTag(),
          magicFilter: MagicFilter(
            filterName: title,
            occurrence: kMostRelevantFilter,
            matchedUploadedIDs: filesToUploadedFileIDs(enteFilesInMagicCache),
          ),
        ),
      );
    },
    hierarchicalSearchFilter: MagicFilter(
      filterName: title,
      occurrence: kMostRelevantFilter,
      matchedUploadedIDs: filesToUploadedFileIDs(enteFilesInMagicCache),
    ),
  );
}

class MagicCacheService {
  static const _lastMagicCacheUpdateTime = "last_magic_cache_update_time";
  static const _kPromptsAssetPath = "assets/discover.json";
  static const _kSearchTabIndex = 3;
  static const _kBackgroundUpdateDebounce = Duration(minutes: 5);

  /// Delay is for cache update to be done not during app init, during which a
  /// lot of other things are happening.
  static const _kCacheUpdateDelay = Duration(seconds: 10);

  final SharedPreferences _prefs;
  late final Logger _logger = Logger((MagicCacheService).toString());

  Future<List<MagicCache>>? _magicCacheFuture;
  Future<List<Prompt>>? _promptFuture;
  final Set<String> _pendingUpdateReason = {};
  bool _isUpdateInProgress = false;
  int _cacheGeneration = 0;
  Timer? _backgroundUpdateTimer;
  bool _refreshWhenCurrentUpdateCompletes = false;

  MagicCacheService(this._prefs) {
    _logger.info("MagicCacheService constructor");
    Bus.instance.on<FileUploadedEvent>().listen((event) {
      queueUpdate("File uploaded");
      _scheduleBackgroundUpdate();
    });
    Bus.instance.on<TabChangedEvent>().listen((event) {
      if (event.source == TabChangedEventSource.pageView &&
          event.selectedIndex == _kSearchTabIndex) {
        _runPendingUpdateForSearch();
      }
    });
    Future.delayed(_kCacheUpdateDelay, () {
      _updateCacheIfTheTimeHasCome();
    });
  }

  String get _lastMagicCacheUpdateKey => isLocalGalleryMode
      ? "${_lastMagicCacheUpdateTime}_offline"
      : _lastMagicCacheUpdateTime;

  Future<void> _resetLastMagicCacheUpdateTime() async {
    await _prefs.setInt(
      _lastMagicCacheUpdateKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  int get lastMagicCacheUpdateTime {
    return _prefs.getInt(_lastMagicCacheUpdateKey) ?? 0;
  }

  int get lastMagicCacheUpdateTimeInMicroseconds {
    return lastMagicCacheUpdateTime * 1000;
  }

  bool get enableDiscover => hasGrantedMLConsent;

  void queueUpdate(String reason) {
    _pendingUpdateReason.add(reason);
  }

  void _scheduleBackgroundUpdate() {
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = Timer(_kBackgroundUpdateDebounce, () {
      _backgroundUpdateTimer = null;
      _updateCache().ignore();
    });
  }

  void _runPendingUpdateForSearch() {
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = null;
    if (_isUpdateInProgress) {
      _refreshWhenCurrentUpdateCompletes = true;
      return;
    }
    _updateCache(interactive: true).ignore();
  }

  Future<void> _updateCacheIfTheTimeHasCome() async {
    if (!enableDiscover) {
      return;
    }
    if (lastMagicCacheUpdateTime <
        DateTime.now()
            .subtract(const Duration(hours: 12))
            .millisecondsSinceEpoch) {
      queueUpdate("Cache is old");
    }
  }

  Future<String> _getCachePath() async {
    final suffix = isLocalGalleryMode ? "_offline" : "";
    return (await getApplicationSupportDirectory()).path +
        "/cache/magic_cache$suffix";
  }

  Future<void> updateCache({bool forced = false}) =>
      _updateCache(forced: forced);

  Future<void> _updateCache({
    bool forced = false,
    bool interactive = false,
  }) async {
    if (!enableDiscover) {
      return;
    }
    if (forced) {
      _pendingUpdateReason.add("Forced update");
    }
    await _updateCacheIfTheTimeHasCome();
    if (FileUploader.instance.hasPendingUploads && !forced && !interactive) {
      _scheduleBackgroundUpdate();
      return;
    }
    if (_pendingUpdateReason.isEmpty) {
      _logger.info(
        "No update needed as ${_pendingUpdateReason.toList()} and isUpdateInProgress $_isUpdateInProgress",
      );
      return;
    }
    if (_isUpdateInProgress) {
      if (!forced && !interactive) {
        _scheduleBackgroundUpdate();
      }
      _logger.info("Magic cache update is already in progress");
      return;
    }
    _logger.info("updating magic cache ${_pendingUpdateReason.toList()}");
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = null;
    final updateReasons = Set<String>.of(_pendingUpdateReason);
    _pendingUpdateReason.removeAll(updateReasons);
    final updateGeneration = _cacheGeneration;
    _isUpdateInProgress = true;
    try {
      final EnteWatch? w = kDebugMode ? EnteWatch("magicCacheWatch") : null;
      w?.start();
      final magicPromptsData = await getPrompts();
      w?.log("loadedPrompts");
      final List<MagicCache> magicCaches = await _nonEmptyMagicResults(
        magicPromptsData,
      );
      w?.log("resultComputed");
      if (updateGeneration != _cacheGeneration) {
        return;
      }
      _magicCacheFuture = Future.value(magicCaches);
      await writeToJsonFile<List<MagicCache>>(
        await _getCachePath(),
        magicCaches,
        MagicCache.encodeListToJson,
      );
      if (updateGeneration != _cacheGeneration) {
        await _deleteCacheFile();
        return;
      }
      w?.log("cacheWritten");
      await _resetLastMagicCacheUpdateTime();
      if (updateGeneration != _cacheGeneration) {
        await _prefs.remove(_lastMagicCacheUpdateKey);
        return;
      }
      w?.logAndReset('done');
      Bus.instance.fire(MagicCacheUpdatedEvent());
    } catch (e, s) {
      if (updateGeneration == _cacheGeneration) {
        _pendingUpdateReason.addAll(updateReasons);
        if (!forced) {
          _scheduleBackgroundUpdate();
        }
      }
      _logger.info("Error updating magic cache", e, s);
    } finally {
      _isUpdateInProgress = false;
      if (_refreshWhenCurrentUpdateCompletes) {
        _refreshWhenCurrentUpdateCompletes = false;
        _updateCache(interactive: true).ignore();
      }
    }
  }

  Future<void> refreshCache() async {
    if (!enableDiscover) {
      return;
    }
    try {
      final prompts = await _readPromptsFromAssets();
      final magicCaches = await _readResultFromDisk();
      _promptFuture = Future.value(prompts);
      _magicCacheFuture = Future.value(magicCaches);
      Bus.instance.fire(MagicCacheUpdatedEvent());
    } catch (e, s) {
      _logger.info("Error refreshing magic cache", e, s);
    }
  }

  Future<List<Prompt>> getPrompts() async {
    if (_promptFuture != null) {
      return _promptFuture!;
    }
    _promptFuture = _readPromptsFromAssets();
    return _promptFuture!;
  }

  Future<List<MagicCache>> getMagicCache() async {
    if (_magicCacheFuture != null) {
      return _magicCacheFuture!;
    }
    _magicCacheFuture = _readResultFromDisk();
    return _magicCacheFuture!;
  }

  Future<List<Prompt>> _readPromptsFromAssets() async {
    final String contents = await rootBundle.loadString(_kPromptsAssetPath);
    final Map<String, dynamic> promptsJson = jsonDecode(contents);
    final List<dynamic> promptData = promptsJson['prompts'];
    return promptData
        .map<Prompt>((jsonItem) => Prompt.fromJson(jsonItem))
        .toList();
  }

  Future<List<MagicCache>> _readResultFromDisk() async {
    _logger.info("Reading magic cache result from disk");
    final cache = await decodeJsonFile<List<MagicCache>>(
      await _getCachePath(),
      MagicCache.decodeJsonToList,
    );
    return cache ?? [];
  }

  Future<void> clearMagicCache() async {
    _cacheGeneration++;
    _magicCacheFuture = null;
    _pendingUpdateReason.clear();
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = null;
    _refreshWhenCurrentUpdateCompletes = false;
    await _prefs.remove(_lastMagicCacheUpdateKey);
    await _deleteCacheFile();
  }

  Future<void> _deleteCacheFile() async {
    final file = File(await _getCachePath());
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<List<GenericSearchResult>> getMagicGenericSearchResult(
    BuildContext context,
  ) async {
    try {
      final EnteWatch? w = kDebugMode
          ? EnteWatch("magicGenericSearchResult")
          : null;
      w?.start();
      final magicCaches = await getMagicCache();
      final List<Prompt> prompts = await getPrompts();
      if (magicCaches.isEmpty) {
        w?.log("No magic cache found");
        return [];
      } else {
        w?.log("cacheFound");
      }
      final List<GenericSearchResult> genericSearchResults = [];
      final promptByTitle = <String, Prompt>{};
      for (final prompt in prompts) {
        promptByTitle[prompt.title] = prompt;
      }
      final List<EnteFile> files = await SearchService.instance
          .getAllFilesForSearch();

      if (!isLocalGalleryMode) {
        final Map<String, List<EnteFile>> magicIdToFiles = {};
        final Map<String, Map<int, int>> promptFileOrder = {};
        final Map<int, List<String>> uploadedIdToMagicTitles = {};
        for (final cache in magicCaches) {
          magicIdToFiles[cache.title] = [];
          promptFileOrder[cache.title] = cache.fileIdToPositionMap;
          for (final uploadedId in cache.fileIdToPositionMap.keys) {
            uploadedIdToMagicTitles
                .putIfAbsent(uploadedId, () => <String>[])
                .add(cache.title);
          }
        }
        for (EnteFile file in files) {
          if (!file.isUploaded) continue;
          final uploadedId = file.uploadedFileID;
          if (uploadedId == null) {
            continue;
          }
          final magicTitles = uploadedIdToMagicTitles[uploadedId];
          if (magicTitles == null) {
            continue;
          }
          for (final magicTitle in magicTitles) {
            if (file.isVideo &&
                (promptByTitle[magicTitle]?.showVideo ?? true) == false) {
              continue;
            }
            magicIdToFiles[magicTitle]!.add(file);
          }
        }
        for (final p in prompts) {
          if (!context.mounted) return const [];
          final genericSearchResult = toGenericSearchResult(
            context,
            p,
            magicIdToFiles[p.title] ?? [],
            promptFileOrder[p.title] ?? {},
          );
          if (genericSearchResult != null) {
            genericSearchResults.add(genericSearchResult);
          }
        }
      } else {
        final cacheByTitle = <String, MagicCache>{};
        final localIntIds = <int>{};
        for (final cache in magicCaches) {
          cacheByTitle[cache.title] = cache;
          if (cache.fileLocalIntIDs != null) {
            localIntIds.addAll(cache.fileLocalIntIDs!);
          }
        }
        if (localIntIds.isNotEmpty) {
          final localIdMap = await OfflineFilesDB.instance.getLocalIdsForIntIds(
            localIntIds,
          );
          final localIdToIntId = <String, int>{};
          for (final entry in localIdMap.entries) {
            localIdToIntId[entry.value] = entry.key;
          }
          final neededLocalIds = localIdMap.values.toSet();
          final localIdToFile = <String, EnteFile>{};
          for (final file in files) {
            final localId = file.localID;
            if (localId != null && neededLocalIds.contains(localId)) {
              localIdToFile[localId] = file;
            }
          }
          for (final p in prompts) {
            final cache = cacheByTitle[p.title];
            final localIntIdsForPrompt =
                cache?.fileLocalIntIDs ?? const <int>[];
            final filesForPrompt = <EnteFile>[];
            for (final localIntId in localIntIdsForPrompt) {
              final localId = localIdMap[localIntId];
              final file = localId != null ? localIdToFile[localId] : null;
              if (file == null) continue;
              if (file.isVideo && !p.showVideo) {
                continue;
              }
              filesForPrompt.add(file);
            }
            final fileIdToPosMap = <int, int>{};
            for (int i = 0; i < filesForPrompt.length; i++) {
              final localId = filesForPrompt[i].localID;
              final fileId = localId != null ? localIdToIntId[localId] : null;
              if (fileId != null) {
                fileIdToPosMap[fileId] = i;
              }
            }
            if (p.recentFirst && filesForPrompt.length > 1) {
              sortLocalGalleryMagicFilesByCreationTime(
                filesForPrompt,
                fileIdToPosMap,
                localIdToIntId,
              );
            }
            if (!context.mounted) return const [];
            final genericSearchResult = toGenericSearchResult(
              context,
              p,
              filesForPrompt,
              fileIdToPosMap,
              localIdToIntId: localIdToIntId,
            );
            if (genericSearchResult != null) {
              genericSearchResults.add(genericSearchResult);
            }
          }
        }
      }
      w?.logAndReset("done");
      return genericSearchResults;
    } catch (e, s) {
      _logger.info("Error getting magic generic search result", e, s);
      return [];
    }
  }

  ///Returns non-empty magic results from magicPromptsData
  ///Length is number of prompts, can be less if there are not enough non-empty
  ///results
  Future<List<MagicCache>> _nonEmptyMagicResults(
    List<Prompt> magicPromptsData,
  ) async {
    final TimeLogger t = TimeLogger();
    final results = <MagicCache>[];
    final List<int> matchCount = [];
    final Map<String, double> queryToScore = {};
    for (Prompt prompt in magicPromptsData) {
      queryToScore[prompt.query] = prompt.minScore;
    }
    final clipResults = await SemanticSearchService.instance
        .getMatchingFileIDsForCommonQueries(queryToScore);
    for (Prompt prompt in magicPromptsData) {
      final List<int> matchedIds = clipResults[prompt.query] ?? [];
      if (matchedIds.isNotEmpty) {
        results.add(
          MagicCache(
            prompt.title,
            isLocalGalleryMode ? const <int>[] : matchedIds,
            fileLocalIntIDs: isLocalGalleryMode ? matchedIds : null,
          ),
        );
      }
      matchCount.add(matchedIds.length);
    }
    _logger.info('magic result count $matchCount $t');
    return results;
  }
}
