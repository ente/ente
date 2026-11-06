import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";

Future<bool> showPublicAlbumJoinConfirmation(BuildContext context) async {
  return await showBottomSheetComponent<bool>(
        context: context,
        builder: (sheetContext) => BottomSheetComponent(
          title: sheetContext.strings.joinAlbumConfirmationTitle,
          closeTooltip: sheetContext.strings.close,
          content: Text(
            sheetContext.strings.publicAlbumJoinApprovalBody,
            style: TextStyles.body.copyWith(
              color: sheetContext.componentColors.textLight,
            ),
          ),
          actions: [
            ButtonComponent(
              label: sheetContext.strings.join,
              shouldSurfaceExecutionStates: false,
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ButtonComponent(
              label: sheetContext.strings.cancel,
              variant: ButtonComponentVariant.secondary,
              shouldSurfaceExecutionStates: false,
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ) ??
      false;
}
