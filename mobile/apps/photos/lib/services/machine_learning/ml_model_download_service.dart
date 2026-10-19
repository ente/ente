import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:photos/service_locator.dart"
    show flagService, hasGrantedMLConsent, isLocalGalleryMode, localSettings;
import "package:photos/services/machine_learning/ml_exceptions.dart";
import "package:photos/src/rust/api/ml_indexing_api.dart" as rust_ml;
import "package:photos/utils/network_util.dart";
import "package:synchronized/synchronized.dart";

class MLModelDownloadService {
  final _logger = Logger("MLModelDownloadService");

  final _downloadModelLock = Lock();
  final _progressController = StreamController<(String, int, int)>.broadcast();

  Stream<(String, int, int)> get progressStream => _progressController.stream;

  Future<String> getAssetsDirectory() async =>
      p.join((await getApplicationSupportDirectory()).path, "assets");

  final _activeModelDownloadTriggers = <bool>{};

  bool _areIndexingModelsDownloaded = false;
  bool _areNonIndexingModelsDownloaded = false;
  bool _retryOnlyIndexingModels = true;

  // ignore: cancel_subscriptions
  StreamSubscription<List<ConnectivityResult>>? _modelDownloadRetrySubscription;

  MLModelDownloadService._privateConstructor();
  static final instance = MLModelDownloadService._privateConstructor();
  factory MLModelDownloadService() => instance;

  bool get areIndexingModelsDownloaded => _areIndexingModelsDownloaded;

  bool areModelsDownloaded({required bool onlyIndexingModels}) {
    return _areIndexingModelsDownloaded &&
        (onlyIndexingModels || _areNonIndexingModelsDownloaded);
  }

  Future<bool> canLoadClipTextModel() async {
    if (await rust_ml.isClipTextDownloaded(
      assetsDir: await getAssetsDirectory(),
      includeVocab: true,
    )) {
      return true;
    }
    return isLocalGalleryMode || await canUseHighBandwidth();
  }

  void invalidateModelDownloadCache({bool includeNonIndexingModels = false}) {
    _areIndexingModelsDownloaded = false;
    if (includeNonIndexingModels) {
      _areNonIndexingModelsDownloaded = false;
    }
  }

  void triggerModelsDownload({required bool onlyIndexingModels}) {
    if (areModelsDownloaded(onlyIndexingModels: onlyIndexingModels) ||
        _activeModelDownloadTriggers.contains(onlyIndexingModels)) {
      return;
    }
    _activeModelDownloadTriggers.add(onlyIndexingModels);
    ensureModelsDownloaded(onlyIndexingModels: onlyIndexingModels)
        .whenComplete(
          () => _activeModelDownloadTriggers.remove(onlyIndexingModels),
        )
        .ignore();
  }

  Future<void> ensureModelsDownloaded({
    required bool onlyIndexingModels,
  }) async {
    return _downloadModelLock.synchronized(() async {
      if (areModelsDownloaded(onlyIndexingModels: onlyIndexingModels)) {
        return;
      }
      if (!hasGrantedMLConsent) {
        _logger.info("Skipping ML model download because ML consent is off");
        await _cancelModelDownloadRetry();
        return;
      }
      if (!localSettings.isMLLocalIndexingEnabled) {
        _logger.info(
          "Skipping ML model download because local indexing is disabled",
        );
        await _cancelModelDownloadRetry();
        return;
      }
      final goodInternet = isLocalGalleryMode || await canUseHighBandwidth();
      if (!goodInternet) {
        _logger.info(
          "Skipping ML model download because high bandwidth connectivity is unavailable",
        );
        return;
      }

      final downloadIndexing = !_areIndexingModelsDownloaded;
      final downloadText =
          !onlyIndexingModels && !_areNonIndexingModelsDownloaded;
      if (!downloadIndexing && !downloadText) return;

      _logger.info(
        onlyIndexingModels
            ? "Downloading indexing ML models"
            : "Downloading all ML models",
      );
      try {
        await for (final update in rust_ml.preloadMlModels(
          assetsDir: await getAssetsDirectory(),
          runFaces: downloadIndexing,
          runClip: downloadIndexing,
          runPets: downloadIndexing && _shouldDownloadPetModels,
          includeClipText: downloadText,
        )) {
          switch (update) {
            case rust_ml.ModelDownloadEvent_Progress():
              _progressController.add((
                update.model,
                update.downloadedBytes.toInt(),
                update.totalBytes?.toInt() ?? 0,
              ));
            case rust_ml.ModelDownloadEvent_Failed():
              final error = update.error;
              if (error is rust_ml.RustMlError_ModelDownloadNetwork) {
                throw ModelDownloadNetworkException(error.message);
              }
              throw error;
          }
        }
      } catch (e, s) {
        _logger.warning(
          "ML model download failed, will retry when high bandwidth "
          "connectivity is available",
          e,
          s,
        );
        _listenForHighBandwidthModelDownloadRetry(
          onlyIndexingModels: onlyIndexingModels,
        );
        rethrow;
      }
      if (!_areIndexingModelsDownloaded) {
        _areIndexingModelsDownloaded = true;
      }
      if (!onlyIndexingModels) {
        _areNonIndexingModelsDownloaded = true;
      }
      await _cancelModelDownloadRetryIfComplete();
      _logger.info(
        onlyIndexingModels
            ? "Downloaded indexing ML models"
            : "Downloaded all ML models",
      );
    });
  }

  bool get _shouldDownloadPetModels {
    return flagService.petEnabled && localSettings.petRecognitionEnabled;
  }

  void _listenForHighBandwidthModelDownloadRetry({
    required bool onlyIndexingModels,
  }) {
    if (_modelDownloadRetrySubscription != null) {
      if (!onlyIndexingModels) {
        _retryOnlyIndexingModels = false;
      }
      return;
    }
    _retryOnlyIndexingModels = onlyIndexingModels;
    _logger.info(
      "Listening for high bandwidth connectivity to retry ML model download",
    );
    _modelDownloadRetrySubscription = Connectivity().onConnectivityChanged
        .listen(
          (connections) {
            unawaited(_retryModelDownloadIfHighBandwidth(connections));
          },
          onError: (Object e, StackTrace s) {
            _logger.warning(
              "Connectivity listener for ML model download retry failed",
              e,
              s,
            );
          },
        );
  }

  Future<void> _retryModelDownloadIfHighBandwidth(
    List<ConnectivityResult> connections,
  ) async {
    if (areModelsDownloaded(onlyIndexingModels: _retryOnlyIndexingModels)) {
      await _cancelModelDownloadRetry();
      return;
    }
    if (!hasGrantedMLConsent) {
      _logger.info(
        "Stopping ML model download retry because ML consent is off",
      );
      await _cancelModelDownloadRetry();
      return;
    }
    if (!localSettings.isMLLocalIndexingEnabled) {
      _logger.info(
        "Stopping ML model download retry because local indexing is disabled",
      );
      await _cancelModelDownloadRetry();
      return;
    }
    if (!(isLocalGalleryMode || await canUseHighBandwidth())) {
      _logger.info(
        "ML model download retry waiting for high bandwidth connectivity: "
        "$connections",
      );
      return;
    }
    _logger.info(
      "High bandwidth connectivity available, retrying ML model download",
    );
    final onlyIndexingModels = _retryOnlyIndexingModels;
    await _cancelModelDownloadRetry();
    triggerModelsDownload(onlyIndexingModels: onlyIndexingModels);
  }

  Future<void> _cancelModelDownloadRetry() async {
    final subscription = _modelDownloadRetrySubscription;
    if (subscription == null) {
      return;
    }
    _modelDownloadRetrySubscription = null;
    _retryOnlyIndexingModels = true;
    await subscription.cancel();
  }

  Future<void> _cancelModelDownloadRetryIfComplete() async {
    if (_modelDownloadRetrySubscription == null) {
      return;
    }
    if (areModelsDownloaded(onlyIndexingModels: _retryOnlyIndexingModels)) {
      await _cancelModelDownloadRetry();
    }
  }
}
