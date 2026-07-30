import "package:logging/logging.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/remote_assets_service.dart";
import "package:photos/utils/network_util.dart";
import "package:synchronized/synchronized.dart";

abstract class MlModelAsset {
  static final _logger = Logger("MlModel");

  String get kModelBucketEndpoint => "https://models.ente.com/";

  String get modelRemotePath;

  String get modelSha256;

  final _downloadModelLock = Lock();

  /// WARNING: If [downloadModel] was not first called, this method will download the model first using high bandwidth.
  Future<String> getModelPath() async {
    return _downloadModelLock.synchronized(() async {
      return RemoteAssetsService.instance.getAssetPath(
        modelRemotePath,
        expectedSha256: modelSha256,
      );
    });
  }

  Future<String?> downloadModelSafe() async {
    if (await RemoteAssetsService.instance.hasAsset(modelRemotePath)) {
      return await RemoteAssetsService.instance.getAssetPath(
        modelRemotePath,
        expectedSha256: modelSha256,
      );
    } else {
      if (isLocalGalleryMode || await canUseHighBandwidth()) {
        return await downloadModel();
      } else {
        _logger.warning(
          'Cannot return model path as it is not available locally and high bandwidth is not available.',
        );
        return null;
      }
    }
  }

  Future<String> downloadModel([bool forceRefresh = false]) async {
    return _downloadModelLock.synchronized(() async {
      if (forceRefresh) {
        final file = await RemoteAssetsService.instance.getAssetIfUpdated(
          modelRemotePath,
          expectedSha256: modelSha256,
        );
        return file?.path ??
            await RemoteAssetsService.instance.getAssetPath(
              modelRemotePath,
              expectedSha256: modelSha256,
            );
      } else {
        return await RemoteAssetsService.instance.getAssetPath(
          modelRemotePath,
          expectedSha256: modelSha256,
        );
      }
    });
  }
}
