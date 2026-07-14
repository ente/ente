import "dart:async" show Timer, unawaited;

import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/cache/lru_map.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import 'package:photos/events/embedding_updated_event.dart';
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/ml_computer.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/services/search_service.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class SemanticSearchService {
  static final _logger = Logger("SemanticSearchService");
  SemanticSearchService._privateConstructor();

  static final SemanticSearchService instance =
      SemanticSearchService._privateConstructor();

  final LRUMap<String, List<double>> _queryEmbeddingCache = LRUMap(20);
  static const kMinimumSimilarityThreshold = 0.175;
  MLDataDB get _mlDataDB =>
      isLocalGalleryMode ? MLDataDB.localGalleryInstance : MLDataDB.instance;
  ClipVectorDB get _vectorDB => isLocalGalleryMode
      ? ClipVectorDB.localGalleryInstance
      : ClipVectorDB.instance;

  bool _hasInitialized = false;
  bool _textModelIsLoaded = false;

  final _cacheLock = Lock();
  bool _imageEmbeddingsAreCached = false;
  bool? _cachedEmbeddingsLocalGallery;
  Timer? _embeddingsCacheTimer;
  final Duration _embeddingsCacheDuration = const Duration(seconds: 60);
  static const Duration _vectorDbMigrationDelay = Duration(seconds: 10);
  Future<void>? _prepareVectorDbFuture;

  Future<(String, List<EnteFile>)>? _searchScreenRequest;
  String? _latestPendingQuery;

  Future<void> init() async {
    if (!hasGrantedMLConsent) return;

    _initializeIfNeeded();
    _scheduleWarmup(delayTextModelLoad: true);
  }

  Future<void> prepareForInteractiveSearch() async {
    if (!hasGrantedMLConsent) return;

    _initializeIfNeeded();
    _scheduleWarmup(delayTextModelLoad: false);
  }

  bool isMagicSearchEnabledAndReady() {
    return hasGrantedMLConsent && _textModelIsLoaded;
  }

  Future<void> _prepareVectorDbForSearch() {
    _prepareVectorDbFuture ??= _prepareVectorDbForSearchInternal();
    return _prepareVectorDbFuture!;
  }

  bool get _shouldUseRustExactSearch =>
      flagService.internalUser &&
      flagService.usearchForSearch &&
      localSettings.semanticSearchExactInRustEnabled;

  bool get _shouldUseVectorDbApproximateSearch =>
      flagService.usearchForSearch && !_shouldUseRustExactSearch;

  void _initializeIfNeeded() {
    if (_hasInitialized) {
      return;
    }

    _logger.info("init called");
    _hasInitialized = true;

    Bus.instance.on<EmbeddingUpdatedEvent>().listen((event) {
      if (_imageEmbeddingsAreCached) {
        MLComputer.instance.clearImageEmbeddingsCache();
        _imageEmbeddingsAreCached = false;
      }
    });
  }

  void _scheduleWarmup({required bool delayTextModelLoad}) {
    if (_shouldUseVectorDbApproximateSearch) {
      unawaited(_prepareVectorDbForSearch());
    }

    if (_textModelIsLoaded) {
      return;
    }

    unawaited(_loadTextModel(delay: delayTextModelLoad));
  }

  Future<void> _prepareVectorDbForSearchInternal() async {
    try {
      if (!_shouldUseVectorDbApproximateSearch) return;
      if (!flagService.hasGrantedMLConsent) return;
      if (!await _vectorDB.checkIfMigrationDone()) {
        await Future.delayed(_vectorDbMigrationDelay);
        if (!_shouldUseVectorDbApproximateSearch) return;
        if (!flagService.hasGrantedMLConsent) return;
        await _mlDataDB.checkMigrateFillClipVectorDB();
      }
      if (await _vectorDB.checkIfMigrationDone()) {
        await _vectorDB.warmupApproxSearch();
      }
    } catch (e, s) {
      _logger.severe("Failed to prepare VectorDB for search", e, s);
    } finally {
      _prepareVectorDbFuture = null;
    }
  }

  // searchScreenQuery should only be used for the user initiate query on the search screen.
  // If there are multiple call tho this method, then for all the calls, the result will be the same as the last query.
  Future<(String, List<EnteFile>)> searchScreenQuery(String query) async {
    if (!isMagicSearchEnabledAndReady()) {
      if (flagService.internalUser) {
        _logger.info(
          "ML global consent: $hasGrantedMLConsent, loaded: $_textModelIsLoaded ",
        );
      }
      return (query, <EnteFile>[]);
    }
    // If there's an ongoing request, just update the last query and return its future.
    if (_searchScreenRequest != null) {
      _latestPendingQuery = query;
      return _searchScreenRequest!;
    } else {
      // No ongoing request, start a new search.
      _searchScreenRequest = getMatchingFiles(query).then((result) {
        // Search completed, reset the ongoing request.
        _searchScreenRequest = null;
        // If there was a new query during the last search, start a new search with the last query.
        if (_latestPendingQuery != null) {
          final String newQuery = _latestPendingQuery!;
          _latestPendingQuery = null; // Reset last query.
          // Recursively call search with the latest query.
          return searchScreenQuery(newQuery);
        }
        return (query, result);
      });
      return _searchScreenRequest!;
    }
  }

  Future<void> clearIndexes() async {
    await _mlDataDB.deleteClipIndexes();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove("sync_time_embeddings_v3");
    _logger.info("Indexes cleared");
  }

  Future<void> _cacheClipVectors() async {
    return _cacheLock.synchronized(() async {
      _resetInactivityTimer();
      if (_imageEmbeddingsAreCached) {
        if (_cachedEmbeddingsLocalGallery != isLocalGalleryMode) {
          await MLComputer.instance.clearImageEmbeddingsCache();
          _imageEmbeddingsAreCached = false;
          _cachedEmbeddingsLocalGallery = null;
        } else {
          return;
        }
      }
      if (_imageEmbeddingsAreCached) {
        return;
      }
      final now = DateTime.now();
      final imageEmbeddings = await _mlDataDB.getAllClipVectors();
      _logger.info(
        "read all ${imageEmbeddings.length} embeddings from DB in ${DateTime.now().difference(now).inMilliseconds} ms",
      );
      await MLComputer.instance.cacheImageEmbeddings(
        imageEmbeddings,
        cacheRustExact: _shouldUseRustExactSearch,
      );
      _imageEmbeddingsAreCached = true;
      _cachedEmbeddingsLocalGallery = isLocalGalleryMode;
      return;
    });
  }

  Future<List<EnteFile>> getMatchingFiles(
    String query, {
    double? similarityThreshold,
  }) async {
    bool showThreshold = false;
    // if the query starts with 0.xxx, the split the query to get score threshold and actual query
    if (query.startsWith(RegExp(r"0\.\d+"))) {
      final parts = query.split(" ");
      if (parts.length > 1) {
        similarityThreshold = double.parse(parts[0]);
        query = parts.sublist(1).join(" ");
        showThreshold = true;
      }
    }
    final textEmbedding = await _getTextEmbedding(query);

    final minimumSimilarity =
        similarityThreshold ?? kMinimumSimilarityThreshold;
    final similarityResults = await _getSimilarities(
      {query: textEmbedding},
      minimumSimilarityMap: {query: minimumSimilarity},
    );
    final queryResults = similarityResults[query] ?? <QueryResult>[];
    // Uncomment if needed for debugging: print query for top ten scores
    // if (kDebugMode) {
    //   for (int i = 0; i < min(10, queryResults.length); i++) {
    //     final result = queryResults[i];
    //     dev.log("Query: $query, Score: ${result.score}, index $i");
    //   }
    // }

    final Map<int, double> fileIDToScoreMap = {};
    for (final result in queryResults) {
      fileIDToScoreMap[result.id] = result.score;
    }

    if (isLocalGalleryMode) {
      return _getLocalGalleryMatchingFiles(
        queryResults,
        fileIDToScoreMap,
        showThreshold,
      );
    }

    final filesMap = await FilesDB.instance.getFileIDToFileFromIDs(
      queryResults.map((e) => e.id).toList(),
    );

    final ignoredCollections = CollectionsService.instance
        .getHiddenCollectionIds();

    final deletedEntries = <int>[];
    final results = <EnteFile>[];

    for (final result in queryResults) {
      final file = filesMap[result.id];
      if (file != null && !ignoredCollections.contains(file.collectionID)) {
        if (showThreshold) {
          file.debugCaption =
              "${fileIDToScoreMap[result.id]?.toStringAsFixed(3)}";
        }
        results.add(file);
      }

      if (file == null) {
        deletedEntries.add(result.id);
      }
    }

    _logger.info(results.length.toString() + " results");

    if (deletedEntries.isNotEmpty) {
      unawaited(_mlDataDB.deleteClipEmbeddings(deletedEntries));
    }

    return results;
  }

  Future<List<EnteFile>> _getLocalGalleryMatchingFiles(
    List<QueryResult> queryResults,
    Map<int, double> fileIDToScoreMap,
    bool showThreshold,
  ) async {
    final localIdMap = await OfflineFilesDB.instance.getLocalIdsForIntIds(
      queryResults.map((e) => e.id),
    );
    final allFiles = await SearchService.instance.getAllFilesForSearch();
    final ignoredCollections = CollectionsService.instance
        .getHiddenCollectionIds();
    final localIdToFile = <String, EnteFile>{};
    for (final file in allFiles) {
      final localId = file.localID;
      if (localId != null) {
        localIdToFile[localId] = file;
      }
    }

    final results = <EnteFile>[];
    final deletedEntries = <int>[];
    for (final result in queryResults) {
      final localId = localIdMap[result.id];
      final file = localId != null ? localIdToFile[localId] : null;
      if (file != null && !ignoredCollections.contains(file.collectionID)) {
        if (showThreshold) {
          file.debugCaption =
              "${fileIDToScoreMap[result.id]?.toStringAsFixed(3)}";
        }
        results.add(file);
      } else {
        deletedEntries.add(result.id);
      }
    }

    if (deletedEntries.isNotEmpty) {
      unawaited(_mlDataDB.deleteClipEmbeddings(deletedEntries));
    }

    return results;
  }

  /// Get matching file IDs for common repeated queries like smart memories and magic cache.
  /// WARNING: Use this method carefully - it uses persistent caching which is only
  /// beneficial for queries that are repeated across app sessions.
  /// For regular user searches, use getMatchingFiles instead.
  Future<Map<String, List<int>>> getMatchingFileIDsForCommonQueries(
    Map<String, double> queryToScore,
  ) async {
    final textEmbeddings = <String, List<double>>{};
    final minimumSimilarityMap = <String, double>{};

    for (final entry in queryToScore.entries) {
      final query = entry.key;
      final score = entry.value;
      // Use cache service instead of _getTextEmbedding
      final textEmbedding = await textEmbeddingsCacheService.getEmbedding(
        query,
      );
      textEmbeddings[query] = textEmbedding;
      minimumSimilarityMap[query] = score;
    }

    final queryResults = await _getSimilarities(
      textEmbeddings,
      minimumSimilarityMap: minimumSimilarityMap,
      maxResults: 0,
    );

    final result = <String, List<int>>{};
    for (final entry in queryResults.entries) {
      final query = entry.key;
      final queryResult = entry.value;
      final fileIDs = <int>[];
      for (final result in queryResult) {
        fileIDs.add(result.id);
      }
      result[query] = fileIDs;
    }
    return result;
  }

  Future<void> _loadTextModel({bool delay = false}) async {
    _logger.info("Initializing ClipText");
    try {
      if (delay) await Future.delayed(const Duration(seconds: 5));
      await MLComputer.instance.warmUpClipTextEncoder();
      _textModelIsLoaded = true;
    } catch (e, s) {
      _logger.severe("Clip text loading failed", e, s);
    }
    _logger.info("Clip text model loaded");
  }

  Future<void> storeClipImageResult(ClipResult clipResult) async {
    final embedding = ClipEmbedding(
      fileID: clipResult.fileID,
      embedding: clipResult.embedding,
      version: clipMlVersion,
    );
    await _mlDataDB.putClip([embedding]);
  }

  Future<void> storeEmptyClipImageResult(EnteFile entefile) async {
    final embedding = ClipEmbedding.empty(entefile.uploadedFileID!);
    await _mlDataDB.putClip([embedding]);
  }

  Future<List<double>> _getTextEmbedding(String query) async {
    _logger.info("Searching for ${kDebugMode ? query : ''}");
    final cachedResult = _queryEmbeddingCache.get(query);
    if (cachedResult != null) {
      return cachedResult;
    }
    final textEmbedding = await MLComputer.instance.runClipText(query);
    _queryEmbeddingCache.put(query, textEmbedding);
    return textEmbedding;
  }

  Future<Map<String, List<QueryResult>>> _getSimilarities(
    Map<String, List<double>> textQueryToEmbeddingMap, {
    required Map<String, double> minimumSimilarityMap,
    int? maxResults,
  }) async {
    // Uncomment if needed for debugging: print query embeddings
    // if (kDebugMode) {
    //   for (final queryText in textQueryToEmbeddingMap.keys) {
    //     final embedding = textQueryToEmbeddingMap[queryText]!;
    //     dev.log("CLIPTEXT Query: $queryText, embedding: $embedding");
    //   }
    // }
    if (await _canUseVectorDbForSearch()) {
      final startTime = DateTime.now();
      try {
        final queryResults = await _computeApproxSimilaritiesWithVectorDb(
          textQueryToEmbeddingMap,
          minimumSimilarityMap,
          maxResults: maxResults,
        );
        final endTime = DateTime.now();
        _logger.info(
          "computingSimilarities (usearch approximate) took for ${textQueryToEmbeddingMap.length} queries " +
              (endTime.millisecondsSinceEpoch -
                      startTime.millisecondsSinceEpoch)
                  .toString() +
              "ms",
        );
        return queryResults;
      } catch (e, s) {
        _logger.severe(
          "VectorDB similarity search failed, falling back to in-memory dot-product",
          e,
          s,
        );
      }
    }

    await _cacheClipVectors();
    if (_shouldUseRustExactSearch) {
      final startTime = DateTime.now();
      try {
        final queryResults = await MLComputer.instance
            .computeBulkSimilaritiesWithRust(
              textQueryToEmbeddingMap,
              minimumSimilarityMap,
            );
        final endTime = DateTime.now();
        _logger.info(
          "computingSimilarities (rust simsimd exact) took for ${textQueryToEmbeddingMap.length} queries " +
              (endTime.millisecondsSinceEpoch -
                      startTime.millisecondsSinceEpoch)
                  .toString() +
              "ms",
        );
        return queryResults;
      } catch (e, s) {
        _logger.severe(
          "Rust exact similarity search failed, falling back to Dart in-memory dot-product",
          e,
          s,
        );
      }
    }

    final startTime = DateTime.now();
    final Map<String, List<QueryResult>> queryResults = await MLComputer
        .instance
        .computeBulkSimilarities(textQueryToEmbeddingMap, minimumSimilarityMap);
    final endTime = DateTime.now();
    _logger.info(
      "computingSimilarities (dot-product) took for ${textQueryToEmbeddingMap.length} queries " +
          (endTime.millisecondsSinceEpoch - startTime.millisecondsSinceEpoch)
              .toString() +
          "ms",
    );
    return queryResults;
  }

  Future<Map<String, List<QueryResult>>> _computeApproxSimilaritiesWithVectorDb(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap, {
    int? maxResults,
  }) async {
    final queryResults = <String, List<QueryResult>>{};
    final bool shouldLimitResults = maxResults != null && maxResults > 0;
    for (final entry in textQueryToEmbeddingMap.entries) {
      final query = entry.key;
      final minimumSimilarity = minimumSimilarityMap[query]!;
      final textEmbedding = entry.value;
      final results = await _vectorDB.searchApproxSimilaritiesWithinThreshold(
        textEmbedding,
        minimumSimilarity,
      );
      if (shouldLimitResults && results.length > maxResults) {
        queryResults[query] = results.sublist(0, maxResults);
      } else {
        queryResults[query] = results;
      }
    }
    return queryResults;
  }

  Future<bool> _canUseVectorDbForSearch() async {
    if (!_shouldUseVectorDbApproximateSearch) return false;
    if (!flagService.hasGrantedMLConsent) return false;
    if (await _vectorDB.checkIfMigrationDone()) return true;
    // Keep interactive search responsive: prepare/migrate in the background and
    // immediately fall back to in-memory similarity search for this request.
    unawaited(_prepareVectorDbForSearch());
    return false;
  }

  void _resetInactivityTimer() {
    _embeddingsCacheTimer?.cancel();
    _embeddingsCacheTimer = Timer(_embeddingsCacheDuration, () {
      _logger.info(
        'Embeddings cache is unused for ${_embeddingsCacheDuration.inSeconds} seconds. Removing cache.',
      );
      if (_imageEmbeddingsAreCached) {
        MLComputer.instance.clearImageEmbeddingsCache();
        _imageEmbeddingsAreCached = false;
      }
    });
  }
}
