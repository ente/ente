import 'dart:async';

import 'package:ente_components/components/bottom_sheet/bottom_sheet_component.dart';
import 'package:ente_components/components/buttons/button_component.dart';
import 'package:flutter/material.dart';

Future<T?> showErrorBottomSheetComponent<T>({
  required BuildContext context,
  required String message,
  String title = 'Error',
  Widget? illustration,
  String? actionLabel,
  FutureOr<void> Function()? onActionTap,
  // Called only by the close button, not other dismissal paths.
  FutureOr<void> Function()? onClose,
  bool showCloseButton = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  Color? barrierColor,
}) {
  return showBottomSheetComponent<T>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    barrierColor: barrierColor,
    builder: (_) => BottomSheetComponent(
      title: title,
      message: message,
      illustration: illustration,
      actions: [
        if (actionLabel != null)
          ButtonComponent(
            label: actionLabel,
            variant: ButtonComponentVariant.secondary,
            onTap: onActionTap,
          ),
      ],
      onClose: onClose,
      showCloseButton: showCloseButton,
    ),
  );
}
