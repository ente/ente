import "dart:io";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/utils/dialog_util.dart";

final _logger = Logger("photo_library_add_permission");

Future<bool> ensurePhotoLibraryAddPermission(BuildContext context) async {
  if (!context.mounted) return false;
  if (!Platform.isIOS) return true;

  PermissionState permission;
  try {
    permission = await permissionService.requestPhotoLibraryAddPermission();
  } catch (e, s) {
    _logger.warning("Could not verify Apple Photos add permission", e, s);
    if (context.mounted) {
      await showGenericErrorDialog(context: context, error: e);
    }
    return false;
  }

  _logger.info("Apple Photos add permission: $permission");
  if (!context.mounted) return false;
  if (permission.hasAccess) return true;

  final isRestricted = permission == PermissionState.restricted;
  await showAlertBottomSheet(
    context,
    title: context.strings.allowPermTitle,
    message: isRestricted
        ? context.strings.photoLibraryAddPermissionRestricted
        : context.strings.photoLibraryAddPermissionRequired,
    assetPath: "assets/ducky_smart_feature.png",
    buttons: isRestricted
        ? null
        : [
            ButtonWidgetV2(
              buttonType: ButtonTypeV2.primary,
              labelText: context.strings.openSettings,
              isInAlert: true,
              shouldSurfaceExecutionStates: false,
              onTap: () async {
                Navigator.of(context).pop();
                await PhotoManager.openSetting();
              },
            ),
          ],
  );
  return false;
}
