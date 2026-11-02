import "dart:async" show Timer;

import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/dart_db.dart";
import 'package:photos/events/embedding_updated_event.dart';
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/machine_learning/ml_computer.dart";
import "package:photos/services/machine_learning/semantic_search/clip_similarity_scan.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:synchronized/synchronized.dart";

class DartClipSimilarityScan implements ClipSimilarityScan {
  static final _logger = Logger("DartClipSimilarityScan");

  DartClipSimilarityScan._() {
    Bus.instance.on<EmbeddingUpdatedEvent>().listen((event) {
      if (_imageEmbeddingsAreCached) {
        MLComputer.instance.clearImageEmbeddingsCache();
        _imageEmbeddingsAreCached = false;
      }
    });
  }

  static final instance = DartClipSimilarityScan._();

  DartMLDataDB get _mlDataDB => isLocalGalleryMode
      ? DartMLDataDB.localGalleryInstance
      : DartMLDataDB.instance;

  final _cacheLock = Lock();
  bool _imageEmbeddingsAreCached = false;
  bool? _cachedEmbeddingsLocalGallery;
  Timer? _embeddingsCacheTimer;
  final Duration _embeddingsCacheDuration = const Duration(seconds: 60);

  @override
  Future<Map<String, List<QueryResult>>> computeSimilarities(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap,
  ) async {
    await _cacheClipVectors();
    return MLComputer.instance.computeBulkSimilarities(
      textQueryToEmbeddingMap,
      minimumSimilarityMap,
    );
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
      await MLComputer.instance.cacheImageEmbeddings(imageEmbeddings);
      _imageEmbeddingsAreCached = true;
      _cachedEmbeddingsLocalGallery = isLocalGalleryMode;
      return;
    });
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
