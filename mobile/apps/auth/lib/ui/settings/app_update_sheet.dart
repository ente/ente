import "package:ente_auth/services/update_service.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_ui/components/app_update_sheet.dart" as shared;
import "package:flutter/material.dart";

const _changelogUrl = "https://ente.com/help/auth/changelog";

Future<void> showAppUpdateSheet(
  BuildContext context, {
  required LatestVersionInfo latestVersionInfo,
}) {
  final updateService = UpdateService.instance;
  return shared.showAppUpdateSheet(
    context,
    version: latestVersionInfo.name!,
    downloadUrl: PlatformDetector.isDesktop()
        ? latestVersionInfo.release!
        : latestVersionInfo.url!,
    changelogUrl: _changelogUrl,
    isCritical: updateService.shouldForceUpdate(latestVersionInfo),
    notificationsEnabled: updateService.updateNotificationsEnabled,
    onNotificationsChanged: updateService.setUpdateNotificationsEnabled,
    useRootNavigator: true,
  );
}
