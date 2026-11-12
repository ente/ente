import "package:connectivity_plus/connectivity_plus.dart";
import "package:photos/service_locator.dart";

Future<bool> canUseHighBandwidth() async {
  final connections = await Connectivity().checkConnectivity();
  return backupSettings.shouldBackupOverMobileData() ||
      connections.contains(ConnectivityResult.wifi) ||
      connections.contains(ConnectivityResult.ethernet) ||
      !connections.contains(ConnectivityResult.mobile);
}
