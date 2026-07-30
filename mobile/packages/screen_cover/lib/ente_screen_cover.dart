import "package:flutter/services.dart";

/// Hides app content from screenshots/recents (Android) and the app switcher (iOS).
class EnteScreenCover {
  EnteScreenCover._();

  static const MethodChannel _channel = MethodChannel("ente_screen_cover");

  static Future<void> enable() => _channel.invokeMethod("enable");

  static Future<void> disable() => _channel.invokeMethod("disable");
}
