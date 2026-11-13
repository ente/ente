import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

class PlatformUtil {
  static TextSelectionControls get selectionControls => Platform.isAndroid
      ? materialTextSelectionControls
      : Platform.isIOS
      ? cupertinoTextSelectionControls
      : desktopTextSelectionControls;

  static Future<void> openWebView(
    BuildContext context,
    String title,
    String url,
  ) async {
    await launchUrlString(url);
  }

  // Needed to fix issue with local_auth on Windows
  // https://github.com/flutter/flutter/issues/122322
  static Future<void> refocusWindows() async {
    if (!Platform.isWindows) return;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.blur();
    await windowManager.show();
    await windowManager.setAlwaysOnTop(false);
  }
}
