import "package:flutter/services.dart";

class EnteScreenCover {
  EnteScreenCover._();

  static const MethodChannel _channel = MethodChannel("ente_screen_cover");

  static Future<void> enable() => _channel.invokeMethod("enable");

  static Future<void> disable() => _channel.invokeMethod("disable");
}
