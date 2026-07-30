import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/update_service.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:url_launcher/url_launcher_string.dart";

Future<void> showAppUpdateBottomSheet(
  BuildContext context, {
  required LatestVersionInfo latestVersionInfo,
}) async {
  final navigator = Navigator.of(context);
  final l10n = context.l10n;
  final shouldForceUpdate = UpdateService.instance.shouldForceUpdate(
    latestVersionInfo,
  );
  final updateMessage = l10n.aNewVersionOfEnteLockerIsAvailable;
  final title = shouldForceUpdate
      ? l10n.criticalUpdateAvailable
      : l10n.updateAvailable;

  await showBottomSheetComponent<void>(
    context: context,
    isDismissible: !shouldForceUpdate,
    enableDrag: !shouldForceUpdate,
    builder: (_) => BottomSheetComponent(
      title: title,
      message: updateMessage,
      illustration: LockerBottomSheetIllustration.warningBlue,
      showCloseButton: !shouldForceUpdate,
      actions: [
        ButtonComponent(
          label: l10n.downloadUpdate,
          onTap: () {
            unawaited(
              launchUrlString(
                latestVersionInfo.url,
                mode: LaunchMode.externalApplication,
              ),
            );
            if (!shouldForceUpdate) {
              navigator.pop();
            }
          },
        ),
      ],
    ),
  );
}
