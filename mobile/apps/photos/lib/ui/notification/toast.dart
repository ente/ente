import "dart:async";
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:photos/ente_theme_data.dart';

void showToast(
  BuildContext context,
  String message, {
  toastLength = Toast.LENGTH_LONG,
  int iosLongToastLengthInSec = 2,
  ToastGravity gravity = ToastGravity.BOTTOM,
  EasyLoadingToastPosition position = EasyLoadingToastPosition.bottom,
}) async {
  if (Platform.isAndroid) {
    await Fluttertoast.cancel();
    if (!context.mounted) return;
    unawaited(
      Fluttertoast.showToast(
        msg: message,
        toastLength: toastLength,
        gravity: gravity,
        timeInSecForIosWeb: 1,
        backgroundColor: Theme.of(context).colorScheme.toastBackgroundColor,
        textColor: Theme.of(context).colorScheme.toastTextColor,
        fontSize: 16.0,
      ),
    );
  } else {
    EasyLoading.instance
      ..backgroundColor = Theme.of(context).colorScheme.toastBackgroundColor
      ..indicatorColor = Theme.of(context).colorScheme.toastBackgroundColor
      ..textColor = Theme.of(context).colorScheme.toastTextColor
      ..userInteractions = true
      ..loadingStyle = EasyLoadingStyle.custom;
    unawaited(
      EasyLoading.showToast(
        message,
        duration: Duration(
          seconds: (toastLength == Toast.LENGTH_LONG
              ? iosLongToastLengthInSec
              : 1),
        ),
        toastPosition: position,
        dismissOnTap: false,
      ),
    );
  }
}

void showShortToast(BuildContext context, String message) {
  showToast(context, message, toastLength: Toast.LENGTH_SHORT);
}
