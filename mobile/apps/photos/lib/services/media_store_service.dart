import "package:flutter/services.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/trash_file.dart";

/// Android MediaStore permission helpers.
class MediaStoreService {
  static const _methodChannel = MethodChannel("io.ente.photos/media_store");

  /// Returns whether Android media management settings are available.
  static Future<bool> isMediaManagementSupported() async {
    return (await _methodChannel.invokeMethod<bool>(
      "isMediaManagementSupported",
    ))!;
  }

  /// Returns whether Ente can manage shared media without user confirmation.
  static Future<bool> canManageMedia() async {
    return (await _methodChannel.invokeMethod<bool>("canManageMedia"))!;
  }

  /// Opens Android settings for granting media management access.
  static Future<void> openManageMediaSettings() async {
    await _methodChannel.invokeMethod<void>("openManageMediaSettings");
  }

  /// Returns image items in Android's device trash, oldest expiry first.
  static Future<List<TrashFile>> getTrashItems() async {
    final items = (await _methodChannel.invokeListMethod<Map<Object?, Object?>>(
      "getTrashItems",
    ))!;
    return items
        .map((item) {
          final metadata = Map<String, dynamic>.from(item);
          final fileSize = metadata.remove("fileSize") as int;
          final deleteBy = metadata.remove("deleteBy") as int;
          final thumbnail = metadata.remove("thumbnail") as Uint8List;
          final file = TrashFile(source: TrashFileSource.system)
            ..applyMetadata(metadata)
            ..fileSize = fileSize
            ..deleteBy = deleteBy;
          ThumbnailInMemoryLruCache.put(file, thumbnail, thumbnailSmallSize);
          ThumbnailInMemoryLruCache.put(file, thumbnail, thumbnailLargeSize);
          return file;
        })
        .toList(growable: false);
  }

  /// Reads an Android trash item without making a temporary file.
  static Future<Uint8List> getTrashFileBytes(EnteFile file) async =>
      (await _methodChannel.invokeMethod<Uint8List>("getTrashFileBytes", {
        "uri": file.localID!,
      }))!;

  /// Opens Android's confirm sheet, then restores or deletes the trash item.
  static Future<bool> updateTrashItem(EnteFile file, bool delete) async =>
      (await _methodChannel.invokeMethod<bool>(
        delete ? "deleteTrashItem" : "restoreTrashItem",
        {"localID": file.localID!},
      ))!;
}
