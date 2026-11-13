import "package:ente_ui/components/app_update_sheet.dart" as shared;
import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/update_service.dart";

const _changelogUrl = "https://ente.com/help/photos/changelog";

Future<void> showAppUpdateSheet(
  BuildContext context, {
  required LatestVersionInfo latestVersionInfo,
}) {
  return shared.showAppUpdateSheet(
    context,
    version: latestVersionInfo.name,
    downloadUrl: latestVersionInfo.url,
    changelogUrl: _changelogUrl,
    isCritical: updateService.shouldForceUpdate(latestVersionInfo),
    notificationsEnabled: updateService.updateNotificationsEnabled,
    onNotificationsChanged: updateService.setUpdateNotificationsEnabled,
  );
}
