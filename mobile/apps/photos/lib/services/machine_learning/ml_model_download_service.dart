import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:logging/logging.dart";
import "package:photos/service_locator.dart"
    show flagService, hasGrantedMLConsent, isLocalGalleryMode, localSettings;
import "package:photos/services/machine_learning/ml_model_assets.dart";
import "package:photos/services/machine_learning/ml_models_overview.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/utils/network_util.dart";
import "package:synchronized/synchronized.dart";

class MLModelDownloadService {
  final _logger = Logger("MLModelDownloadService");

  final _downloadModelLock = Lock();

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
    final hasModel = await RemoteAssetsService.instance.hasAsset(
      ClipTextModel.instance.modelRemotePath,
    );
    final hasVocab = await RemoteAssetsService.instance.hasAsset(
      ClipTextModel.instance.vocabRemotePath,
    );
    if (hasModel && hasVocab) {
      return true;
    }
    return isLocalGalleryMode || await canUseHighBandwidth();
  }

  /// Invalidate the download cache so the next ML run re-enters
  /// [ensureModelsDownloaded], which checks consent, local indexing, bandwidth,
  /// and downloads any newly required models.
  void invalidateModelDownloadCache({bool includeNonIndexingModels = false}) {
    _areIndexingModelsDownloaded = false;
    if (includeNonIndexingModels) {
      _areNonIndexingModelsDownloaded = false;
    }
  }

  void triggerModelsDownload({required bool onlyIndexingModels}) {
    if (!areModelsDownloaded(onlyIndexingModels: onlyIndexingModels)) {
      unawaited(ensureModelsDownloaded(onlyIndexingModels: onlyIndexingModels));
    }
  }

  Future<void> ensureModelsDownloaded({
    required bool onlyIndexingModels,
    bool forceRefresh = false,
  }) async {
    return _downloadModelLock.synchronized(() async {
      if (!forceRefresh &&
          areModelsDownloaded(onlyIndexingModels: onlyIndexingModels)) {
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

      final modelsToDownload = <Future<void>>[];
      if (forceRefresh || !_areIndexingModelsDownloaded) {
        modelsToDownload.addAll(_indexingModelDownloads(forceRefresh));
      }
      if (!onlyIndexingModels &&
          (forceRefresh || !_areNonIndexingModelsDownloaded)) {
        modelsToDownload.addAll(_nonIndexingModelDownloads(forceRefresh));
      }
      if (modelsToDownload.isEmpty) {
        return;
      }

      _logger.info(
        onlyIndexingModels
            ? "Downloading indexing ML models"
            : "Downloading all ML models",
      );
      try {
        await Future.wait(modelsToDownload);
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
      if (forceRefresh || !_areIndexingModelsDownloaded) {
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

  List<Future<void>> _indexingModelDownloads(bool forceRefresh) {
    final models = <MLModels>[
      ...coreIndexingModels,
      if (_shouldDownloadPetModels) ...petIndexingModels,
    ];
    return [
      for (final model in models) model.model.downloadModel(forceRefresh),
    ];
  }

  List<Future<void>> _nonIndexingModelDownloads(bool forceRefresh) {
    return [
      for (final model in nonIndexingModels)
        model.model.downloadModel(forceRefresh),
      RemoteAssetsService.instance.getAssetPath(
        ClipTextModel.instance.vocabRemotePath,
        refetch: forceRefresh,
        expectedSha256: ClipTextModel.instance.vocabSha256,
      ),
    ];
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
