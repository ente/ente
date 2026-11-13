import "dart:async";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/map/map_screen.dart";
import "package:photos/ui/notification/toast.dart";

Future<void> openSearchMap(BuildContext context) async {
  if (!mapEnabled) {
    try {
      await setMapEnabled(true);
      if (!context.mounted) {
        return;
      }
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      showShortToast(context, context.strings.somethingWentWrong);
      return;
    }
  }

  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MapScreen(
          filesFutureFn: SearchService.instance.getAllFilesForSearch,
        ),
      ),
    ),
  );
}
