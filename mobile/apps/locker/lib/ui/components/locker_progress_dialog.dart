import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

Future<LockerProgressDialog> showLockerProgressDialog(
  BuildContext context,
  String message, {
  bool isDismissible = false,
}) async {
  final dialog = showLoadingComponent(
    context,
    message,
    isDismissible: isDismissible,
  );
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
  return LockerProgressDialog._(
    true,
    dialog.isShowing,
    dialog.update,
    dialog.hide,
  );
}

class LockerProgressDialog {
  const LockerProgressDialog._(
    this.didShow,
    this.isShowing,
    this.update,
    this.hide,
  );

  final bool didShow;
  final bool Function() isShowing;
  final void Function({String? message}) update;
  final Future<void> Function() hide;
}
