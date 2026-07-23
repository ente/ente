import "package:flutter/services.dart";

/// Android MediaStore permission helpers.
class MediaStoreService {
  static const _methodChannel = MethodChannel("io.ente.photos/media_store");

  /// Returns whether Android media management settings are available.
  static Future<bool> isMediaManagementSupported() async {
    final result = await _methodChannel.invokeMethod<bool>(
      "isMediaManagementSupported",
    );
    if (result == null) {
      throw AssertionError("isMediaManagementSupported returned null");
    }
    return result;
  }

  /// Returns whether Ente can manage shared media without user confirmation.
  static Future<bool> canManageMedia() async {
    final result = await _methodChannel.invokeMethod<bool>("canManageMedia");
    if (result == null) {
      throw AssertionError("canManageMedia returned null");
    }
    return result;
  }

  /// Opens Android settings for granting media management access.
  static Future<void> openManageMediaSettings() async {
    await _methodChannel.invokeMethod<void>("openManageMediaSettings");
  }
}
