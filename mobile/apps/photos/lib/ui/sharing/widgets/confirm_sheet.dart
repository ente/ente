import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/utils/dialog_util.dart";

Future<bool> showDestructiveConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  required FutureOr<void> Function() onConfirm,
}) async {
  final result = await showBottomSheetComponent<bool>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: title,
      content: Text(
        body,
        style: TextStyles.body.copyWith(
          color: sheetContext.componentColors.textLight,
        ),
      ),
      actions: [
        ButtonComponent(
          label: actionLabel,
          variant: ButtonComponentVariant.critical,
          size: ButtonComponentSize.large,
          onTap: () async {
            try {
              await onConfirm();
            } catch (error) {
              if (sheetContext.mounted) {
                await showGenericErrorDialog(
                  context: sheetContext,
                  error: error,
                );
              }
              rethrow;
            }
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop(true);
            }
          },
        ),
      ],
    ),
  );
  return result ?? false;
}
