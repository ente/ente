import "dart:io";

import "package:collection/collection.dart";
import "package:flutter/services.dart";
import "package:photos/core/constants.dart";
import "package:photos/utils/device_info.dart";

/// Android MediaStore helpers.
class MediaStoreService {
  static const _methodChannel = MethodChannel("io.ente.photos/media_store");

  /// Returns whether Android media management settings are available.
  static Future<bool> isMediaManagementSupported() async {
    return Platform.isAndroid &&
        !await isAndroidSDKVersionLowerThan(android12SDKINT);
  }

  /// Returns whether Ente Photos can manage shared media without user confirmation.
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

  /// Restores trashed files with the given Android MediaStore content URIs.
  static Future<void> restoreTrashedFiles(List<String> uris) =>
      _sendInBatches("restoreTrashedFiles", uris);

  /// Permanently deletes trashed files with the given MediaStore content URIs.
  static Future<void> permanentlyDeleteTrashedFiles(List<String> uris) =>
      _sendInBatches("permanentlyDeleteTrashedFiles", uris);

  static Future<void> _sendInBatches(String method, List<String> uris) async {
    for (final batch in uris.slices(2000)) {
      await _methodChannel.invokeMethod<void>(method, {"uris": batch});
    }
  }
}
