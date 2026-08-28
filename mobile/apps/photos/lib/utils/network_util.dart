import "package:connectivity_plus/connectivity_plus.dart";
import "package:dio/dio.dart";
import "package:photos/service_locator.dart";

bool isNetworkDioException(Object error) =>
    error is DioException &&
    const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.unknown,
    }.contains(error.type);

Future<bool> canUseHighBandwidth() async {
  // A VPN can be reported alongside Wi-Fi or mobile.
  final List<ConnectivityResult> connections = await (Connectivity()
      .checkConnectivity());
  bool canUploadUnderCurrentNetworkConditions = true;
  if (!backupSettings.shouldBackupOverMobileData()) {
    if (connections.any((element) => element == ConnectivityResult.mobile)) {
      canUploadUnderCurrentNetworkConditions = false;
    }
  }
  final canDownloadOverMobileData = backupSettings.shouldBackupOverMobileData();
  return canUploadUnderCurrentNetworkConditions || canDownloadOverMobileData;
}
