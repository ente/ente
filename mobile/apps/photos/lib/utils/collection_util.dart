import "package:android_intent_plus/android_intent.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/utils/dialog_util.dart";

Future<void> requestPermissionToOpenLinksInApp(
  BuildContext context,
  String packageName,
) async {
  final logger = Logger("in-app-links request");
  logger.info("Requesting to allow opening public links in-app");
  try {
    final choice = await showChoiceActionSheet(
      isDismissible: false,
      context,
      title: AppLocalizations.of(context).seePublicAlbumLinksInApp,
      body: AppLocalizations.of(context).allowAppToOpenSharedAlbumLinks,
      firstButtonLabel: AppLocalizations.of(context).allow,
    );
    if (choice!.action == ButtonAction.first) {
      final AndroidIntent intent;
      if (packageName == 'io.ente.photos.independent') {
        intent = const AndroidIntent(
          action: 'android.settings.APP_OPEN_BY_DEFAULT_SETTINGS',
          package: 'io.ente.photos.independent',
          data: 'package:io.ente.photos.independent',
        );
        await intent.launch();
      } else if (packageName == 'io.ente.photos.fdroid') {
        intent = const AndroidIntent(
          action: 'android.settings.APP_OPEN_BY_DEFAULT_SETTINGS',
          package: 'io.ente.photos.fdroid',
          data: 'package:io.ente.photos.fdroid',
        );
        await intent.launch();
      }
      await localSettings.setConfiguredLinksInAppPermissions(true);
      logger.info("In-app links permissions granted");
    } else {
      await localSettings.setConfiguredLinksInAppPermissions(true);
      logger.info("In-app links permissions not granted");
    }
  } catch (e) {
    logger.severe("Failed to req deeplink permission for album links", e);
  }
}
